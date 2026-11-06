import Foundation
import Network
import Security
import CryptoKit
import Combine

// Network.framework callbacks and all model mutations use the main queue.
final class TVConnection: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
    @Published var status = "Choose your Chromecast"
    @Published var connected = false
    @Published var waitingForPIN = false
    @Published var volume: Int?          // 0...100, as reported by the TV
    @Published var muted = false
    @Published private var reportedModel: String?
    private var nameKey: String { "tvName:" + host.lowercased() }
    /// Name shown in the header: the discovered network name, else the model the TV reports.
    var displayName: String {
        if let saved = UserDefaults.standard.string(forKey: nameKey), !saved.isEmpty { return saved }
        if let reportedModel, !reportedModel.isEmpty { return reportedModel }
        return "Google TV"
    }
    func remember(name: String, for host: String) {
        let key = "tvName:" + host.lowercased()
        guard UserDefaults.standard.string(forKey: key) != name else { return }
        UserDefaults.standard.set(name, forKey: key)
        objectWillChange.send()
    }
    @Published var error: String?
    private var socket: NWConnection?
    private var frames = FrameBuffer()
    private var client: ClientIdentity?
    private var serverKey: SecKey?
    private var timer: Timer?
    private var retry: DispatchWorkItem?
    private var pairing = false
    private var wantsConnection = false
    private var generation = UUID()
    private var features: UInt64 = 0
    private var imeCounter: UInt64 = 0
    private var fieldCounter: UInt64 = 0
    private var attempts = 0
    private var phase = 0
    private var pinKey: String { "tvPin:" + host.lowercased() }

    func connect() {
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { error = "Select a device or enter its IP address."; return }
        wantsConnection = true; attempts = 0
        UserDefaults.standard.set(host, forKey: "tvHost")
        open(pair: UserDefaults.standard.data(forKey: pinKey) == nil)
    }
    func pairAgain() {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        wantsConnection = true; attempts = 0
        UserDefaults.standard.set(host, forKey: "tvHost")
        open(pair: true)
    }
    func suspend() {
        wantsConnection = false; close(); status = "Disconnected"
    }
    private func close() {
        generation = UUID(); retry?.cancel(); timer?.invalidate()
        socket?.stateUpdateHandler = nil; socket?.cancel(); socket = nil
        connected = false; waitingForPIN = false; volume = nil; muted = false; reportedModel = nil
        frames = FrameBuffer(); serverKey = nil
    }
    private func open(pair: Bool) {
        close(); pairing = pair; phase = 0; error = nil
        status = pair ? "Starting pairing…" : "Connecting…"
        do { client = try ClientIdentity.load() }
        catch { fail("Could not create the phone’s pairing identity: \(error)"); return }
        guard let client, let identity = sec_identity_create(client.identity) else {
            fail("Could not load the pairing identity."); return
        }
        let token = generation
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, trust, complete in
            guard let self, self.generation == token else { complete(false); return }
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let key = SecTrustCopyKey(ref),
                  let bytes = SecKeyCopyExternalRepresentation(key, nil) as Data? else { complete(false); return }
            self.serverKey = key
            // First pairing is authenticated by the TV's PIN; future connections pin its key.
            complete(pair || UserDefaults.standard.data(forKey: self.pinKey) == bytes)
        }, .main)
        let tcp = NWProtocolTCP.Options(); tcp.connectionTimeout = 10
        let connection = NWConnection(host: NWEndpoint.Host(host), port: pair ? 6467 : 6466,
                                      using: NWParameters(tls: tls, tcp: tcp))
        socket = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == token else { return }
            switch state {
            case .ready:
                self.receive(token)
                if pair {
                    self.phase = 1
                    self.sendPair(10, PB.string(1, "atvremote") + PB.string(2, "My iPhone Remote"))
                }
            case .failed(let error), .waiting(let error):
                self.fail("Connection failed: \(error.localizedDescription)")
            default: break
            }
        }
        connection.start(queue: .main)
        deadline(12)
    }
    private func deadline(_ seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.fail("The Chromecast stopped responding. Check Wi-Fi or use Pair again if its pairing was reset.")
        }
    }
    private func fail(_ message: String) {
        let shouldRetry = wantsConnection && !pairing && attempts < 3
        close(); error = message; status = "Disconnected"
        if shouldRetry {
            attempts += 1
            status = "Reconnecting (\(attempts)/3)…"
            let job = DispatchWorkItem { [weak self] in self?.open(pair: false) }
            retry = job
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempts * 2), execute: job)
        }
    }
    private func send(_ message: Data) {
        let token = generation
        socket?.send(content: PB.varint(UInt64(message.count)) + message, completion: .contentProcessed { [weak self] error in
            guard let self, self.generation == token else { return }
            if let error { self.fail("Command failed: \(error.localizedDescription)") }
        })
    }
    private func receive(_ token: UUID) {
        socket?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, self.generation == token else { return }
            if let error { self.fail(error.localizedDescription); return }
            if complete { self.fail("The TV closed the connection."); return }
            do {
                if let data {
                    for message in try self.frames.append(data) {
                        if self.generation != token { return }
                        if self.pairing { try self.handlePair(message) }
                        else { try self.handleRemote(message) }
                    }
                }
                if self.generation == token { self.receive(token) }
            } catch { self.fail("Unexpected response from the TV: \(error)") }
        }
    }
    private func sendPair(_ field: Int, _ payload: Data) {
        send(PB.int(1, 2) + PB.int(2, 200) + PB.blob(field, payload))
        deadline(12)
    }
    private func handlePair(_ data: Data) throws {
        let fields = try PB.fields(data)
        guard fields.number(2) == 200 else { fail("Pairing was rejected. Try Pair again."); return }
        let encoding = PB.int(1, 3) + PB.int(2, 6)
        if fields.bytes(11) != nil && phase == 1 {
            phase = 2; sendPair(20, PB.blob(1, encoding) + PB.int(3, 1))
        } else if fields.bytes(20) != nil && phase == 2 {
            phase = 3; sendPair(30, PB.blob(1, encoding) + PB.int(2, 1))
        } else if fields.bytes(31) != nil && phase == 3 {
            phase = 4; waitingForPIN = true; status = "Enter the code shown on your TV"; deadline(120)
        } else if fields.bytes(41) != nil && phase == 5 {
            guard let serverKey, let bytes = SecKeyCopyExternalRepresentation(serverKey, nil) as Data? else { throw IdentityError.encoding }
            UserDefaults.standard.set(bytes, forKey: pinKey)
            open(pair: false)
        } else { fail("Unexpected pairing step. Try Pair again.") }
    }
    func submitPIN(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digits = Array(code)
        guard phase == 4, digits.count == 6,
              let check = UInt8(String(digits[0...1]), radix: 16),
              let a = UInt8(String(digits[2...3]), radix: 16),
              let b = UInt8(String(digits[4...5]), radix: 16), let client, let serverKey else {
            error = "Enter all six hexadecimal characters shown on the TV."; return
        }
        do {
            let material = try DER.rsaNumbers(client.publicKey) + DER.rsaNumbers(serverKey) + Data([a, b])
            let digest = Data(SHA256.hash(data: material))
            guard digest.first == check else { error = "That code doesn’t match this TV. Check it and try again."; return }
            phase = 5; waitingForPIN = false; error = nil
            sendPair(40, PB.blob(1, digest)); status = "Finishing pairing…"
        } catch { fail("Could not verify the pairing code: \(error)") }
    }
    private func handleRemote(_ data: Data) throws {
        let fields = try PB.fields(data)
        deadline(20)
        for field in fields {
            let payload = try PB.fields(field.bytes)
            switch field.number {
            case 1:
                features = payload.number(1) & 615 // ping, keys, IME, power, volume, links
                if let info = payload.bytes(2), let infoFields = try? PB.fields(info) {
                    let model = infoFields.bytes(1).flatMap { String(data: $0, encoding: .utf8) }
                    let vendor = infoFields.bytes(2).flatMap { String(data: $0, encoding: .utf8) }
                    reportedModel = [vendor, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                }
                guard features & 2 != 0 else { fail("The TV does not offer remote key control."); return }
                let info = PB.string(1, "iPhone") + PB.string(2, "Personal Remote") + PB.int(3, 1)
                    + PB.string(4, "1") + PB.string(5, "local.googletv.remote") + PB.string(6, "1.0")
                send(PB.blob(1, PB.int(1, features) + PB.blob(2, info)))
            case 2: send(PB.blob(2, PB.int(1, features)))
            case 3: fail("The TV reported a protocol error."); return
            case 8: send(PB.blob(9, PB.int(1, payload.number(1))))
            case 21:
                imeCounter = payload.number(1); fieldCounter = payload.number(2)
            case 40:
                connected = true; attempts = 0; error = nil; status = "Connected"
            case 50:
                let maximum = payload.number(6), level = payload.number(7)
                if maximum > 0 { volume = Int((Double(min(level, maximum)) / Double(maximum) * 100).rounded()) }
                muted = payload.number(8) != 0
            default: break
            }
        }
    }
    func key(_ code: UInt64) {
        guard connected else { error = "Connect to your Chromecast first."; return }
        send(PB.blob(10, PB.int(1, code) + PB.int(2, 3)))
    }
    func sendText(_ text: String) {
        guard connected, features & 4 != 0 else { error = "Keyboard input isn’t available on this connection."; return }
        guard !text.isEmpty else { return }
        let end = UInt64(max(0, text.utf16.count - 1))
        let object = PB.int(1, end) + PB.int(2, end) + PB.string(3, text)
        send(PB.blob(21, PB.int(1, imeCounter) + PB.int(2, fieldCounter)
            + PB.blob(3, PB.int(1, 1) + PB.blob(2, object))))
    }
    func launch(_ link: String) {
        guard connected, features & 512 != 0 else { error = "App shortcuts aren’t available on this connection."; return }
        send(PB.blob(90, PB.string(1, link)))
    }
}

final class TVDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var devices: [String: String] = [:]
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    override init() { super.init(); browser.delegate = self }
    func start() { browser.stop(); services.removeAll(); devices.removeAll(); browser.searchForServices(ofType: "_androidtvremote2._tcp.", inDomain: "local.") }
    func stop() { browser.stop(); services.forEach { $0.stop() }; services.removeAll() }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service); service.delegate = self; service.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        devices.removeValue(forKey: service.name)
        services.removeAll { $0 == service }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let hostname = sender.hostName { devices[sender.name] = hostname }
    }
}
