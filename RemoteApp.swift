import SwiftUI
import UIKit

@main
struct RemoteApp: App {
    var body: some Scene { WindowGroup { RemoteView() } }
}

// Commands are routed to the authenticated Wi-Fi connection or experimental BLE backup.
enum RemoteCommand: String {
    case up, down, left, right, select, home, back, power
    case volumeUp, volumeDown, mute, channelUp, channelDown, microphone
}

struct RemoteView: View {
    @StateObject private var tv = TVConnection()
    @StateObject private var discovery = TVDiscovery()
    @StateObject private var bluetooth = BluetoothBackup()
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboard = false
    @State private var settings = false
    @State private var apps = false
    @State private var text = ""
    @State private var pin = ""
    @State private var wasBackgrounded = false
    // Indigo / neon purple theme
    private let background = Color(red: 0.055, green: 0.047, blue: 0.10)
    private let surface = Color(red: 0.13, green: 0.11, blue: 0.21)
    private let indigo = Color(red: 0.33, green: 0.23, blue: 0.96)
    private let neon = Color(red: 0.80, green: 0.32, blue: 1.0)
    private let ink = Color(red: 0.90, green: 0.87, blue: 1.0)
    private var accent: LinearGradient {
        LinearGradient(colors: [neon, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        GeometryReader { geometry in
            let padSize = min(geometry.size.width - 70, geometry.size.height * 0.40)
            VStack(spacing: 0) {
                // Top bar: settings, connected TV, power
                HStack(spacing: 12) {
                    roundButton("gearshape.fill", label: "Settings", size: 44) { settings = true }
                    Button { settings = true } label: {
                        HStack(spacing: 8) {
                            Circle().fill(tv.connected || bluetooth.ready ? neon : Color.gray)
                                .frame(width: 8, height: 8)
                                .shadow(color: neon.opacity(tv.connected ? 0.9 : 0), radius: 4)
                            Text(tv.connected ? tv.displayName : "Choose TV")
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 44)
                        .background(surface, in: Capsule())
                    }
                    roundButton("power", label: "Power", size: 44, tint: Color(red: 1, green: 0.36, blue: 0.58)) { command(.power) }
                }
                .padding(.horizontal, 20).padding(.top, 10)

                Spacer(minLength: 12)
                dpad(padSize)
                Spacer(minLength: 12)

                // Navigation strip
                HStack(spacing: 0) {
                    stripButton("arrow.uturn.backward", label: "Back") { command(.back) }
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 26)
                    stripButton("house.fill", label: "Home") { command(.home) }
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 26)
                    stripButton("playpause.fill", label: "Play or pause") { sendKey(85) }
                }
                .frame(height: 58).background(surface, in: Capsule())
                .padding(.horizontal, 20)

                Text(!tv.connected && bluetooth.ready ? "Bluetooth backup • experimental" : (tv.error ?? tv.status))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.vertical, 12)

                // Volume + channel rockers, then utility buttons
                HStack(spacing: 12) {
                    rocker(tv.muted ? "MUTE" : "VOL", up: .volumeUp, down: .volumeDown, upSymbol: "plus", downSymbol: "minus",
                           upLabel: "Volume up", downLabel: "Volume down",
                           fill: tv.muted ? 0 : (tv.volume.map { Double($0) / 100 } ?? 0))
                    rocker("CH", up: .channelUp, down: .channelDown, upSymbol: "chevron.up", downSymbol: "chevron.down",
                           upLabel: "Channel up", downLabel: "Channel down", fill: nil)
                    Spacer(minLength: 8)
                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                        GridRow {
                            roundButton(tv.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Mute", size: 72) { command(.mute) }
                            roundButton("keyboard", label: "Keyboard", size: 72) { keyboard = true }
                        }
                        GridRow {
                            roundButton("square.grid.2x2.fill", label: "Apps", size: 72) { apps = true }
                            roundButton("slider.horizontal.3", label: "TV settings", size: 72) { sendKey(176) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(ink).buttonStyle(.plain)
        .tint(neon)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $settings) {
            NavigationStack {
                List {
                    Section("Chromecast on your Wi-Fi") {
                        ForEach(discovery.devices.keys.sorted(), id: \.self) { name in
                            Button(name) {
                                tv.host = discovery.devices[name] ?? ""
                                tv.remember(name: name, for: tv.host)
                                tv.connect()
                            }
                        }
                        Button("Scan again") { discovery.start() }
                    }
                    Section("Connect manually") {
                        TextField("Chromecast IP address or hostname", text: $tv.host)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(tv.waitingForPIN)
                        Button("Connect / reconnect") { tv.connect() }
                        Button("Pair again") { tv.pairAgain() }
                        Text(tv.status)
                        if let error = tv.error { Text(error).foregroundStyle(.orange) }
                    }
                    if tv.waitingForPIN {
                        Section("Code shown on your TV") {
                            TextField("Six-character code", text: $pin)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            Button("Pair") { tv.submitPIN(pin); pin = "" }
                        }
                    }
                    Section {
                        Text("Keep both devices on the same Wi-Fi and allow Local Network access. Power and volume depend on your TV and Chromecast settings.")
                    }
                    Section("Experimental Bluetooth backup") {
                        Text(bluetooth.status)
                        Button("Pair Bluetooth TV") { bluetooth.startPairing() }
                        if bluetooth.enabled { Button("Turn Bluetooth backup off") { bluetooth.stop() } }
                        Text("Pair ‘My TV Remote’ from the Chromecast’s Remotes & accessories settings. When Wi-Fi is disconnected, supported buttons use Bluetooth if the TV has subscribed. Keep this app open. Chromecast compatibility is unverified; text and app shortcuts use Wi-Fi.")
                            .font(.footnote)
                    }
                }.navigationTitle("Your Google TV")
                    .toolbar { Button("Done") { settings = false } }
            }.tint(neon).onAppear { discovery.start() }
        }
        .sheet(isPresented: $keyboard) {
            NavigationStack {
                Form {
                    TextField("Type to search", text: $text)
                    Button("Send text") { tv.sendText(text) }.disabled(!tv.connected || text.isEmpty)
                    Button("Enter / search") { sendKey(66) }.disabled(!tv.connected && !bluetooth.ready)
                    Text("Select a text field on your TV first. You can also use the iPhone keyboard’s dictation button.").font(.footnote)
                }.navigationTitle("Keyboard")
                    .toolbar { Button("Done") { keyboard = false } }
            }.tint(neon).presentationDetents([.medium])
        }
        .confirmationDialog("App shortcuts", isPresented: $apps, titleVisibility: .visible) {
            Button("YouTube") { tv.launch("https://www.youtube.com") }
            Button("Netflix") { tv.launch("https://www.netflix.com") }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            discovery.start()
            if tv.host.isEmpty { settings = true } else { tv.connect() }
        }
        .onReceive(discovery.$devices) { devices in
            // Learn the friendly name (e.g. "Living Room TV") of the TV in use.
            let dots = CharacterSet(charactersIn: ".")
            let current = tv.host.lowercased().trimmingCharacters(in: dots)
            for (name, host) in devices where host.lowercased().trimmingCharacters(in: dots) == current {
                tv.remember(name: name, for: tv.host)
            }
        }
        .onChange(of: tv.waitingForPIN) { _, waiting in if waiting { settings = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && wasBackgrounded {
                wasBackgrounded = false
                if !tv.host.isEmpty { tv.connect() }
            }
            if phase == .background { wasBackgrounded = true; tv.suspend() }
        }
    }

    private func command(_ value: RemoteCommand) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let keys: [RemoteCommand: UInt64] = [.up: 19, .down: 20, .left: 21, .right: 22,
            .select: 23, .home: 3, .back: 4, .power: 26, .volumeUp: 24, .volumeDown: 25,
            .mute: 164, .channelUp: 166, .channelDown: 167, .microphone: 84]
        if let code = keys[value] { sendKey(code) }
    }

    private func sendKey(_ code: UInt64) {
        if tv.connected { tv.key(code) }
        else if !bluetooth.key(code) { tv.key(code) }
    }

    private func dpad(_ size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.14, blue: 0.28), Color(red: 0.08, green: 0.07, blue: 0.14)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: neon.opacity(0.35), radius: 24)
            Circle().strokeBorder(accent, lineWidth: 2)
            direction("chevron.up", .up).offset(y: -size * 0.34)
            direction("chevron.down", .down).offset(y: size * 0.34)
            direction("chevron.left", .left).offset(x: -size * 0.34)
            direction("chevron.right", .right).offset(x: size * 0.34)
            Button { command(.select) } label: {
                Circle().fill(LinearGradient(colors: [neon, indigo], startPoint: .top, endPoint: .bottom))
                    .overlay(Text("OK").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white))
                    .shadow(color: neon.opacity(0.55), radius: 14)
            }
            .frame(width: size * 0.34, height: size * 0.34)
            .accessibilityLabel("OK")
        }
        .frame(width: size, height: size)
    }

    private func direction(_ symbol: String, _ value: RemoteCommand) -> some View {
        Button { command(value) } label: {
            Image(systemName: symbol).font(.system(size: 26, weight: .bold))
                .frame(width: 64, height: 64).contentShape(Rectangle())
        }.accessibilityLabel(value.rawValue)
    }

    private func roundButton(_ symbol: String, label: String, size: CGFloat, tint: Color? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(surface)
                .overlay(Image(systemName: symbol).font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(tint ?? ink))
                .frame(width: size, height: size)
        }.accessibilityLabel(label)
    }

    private func stripButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.accessibilityLabel(label)
    }

    /// Vertical rocker. When `fill` is set, a neon level rises and falls with it (0...1).
    private func rocker(_ title: String, up: RemoteCommand, down: RemoteCommand, upSymbol: String, downSymbol: String,
                        upLabel: String, downLabel: String, fill: Double?) -> some View {
        VStack(spacing: 0) {
            Button { command(up) } label: {
                Image(systemName: upSymbol).font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.accessibilityLabel(upLabel)
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7).padding(.vertical, 6)
            Button { command(down) } label: {
                Image(systemName: downSymbol).font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.accessibilityLabel(downLabel)
        }
        .frame(width: 60, height: 172)
        .background {
            ZStack(alignment: .bottom) {
                Capsule().fill(surface)
                if let fill {
                    Rectangle()
                        .fill(LinearGradient(colors: [neon, indigo], startPoint: .top, endPoint: .bottom))
                        .frame(height: 172 * min(max(fill, 0), 1))
                        .animation(.easeOut(duration: 0.2), value: fill)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(fill == nil ? Color.clear : neon.opacity(0.5), lineWidth: 1))
        }
    }
}

#if !XTOOL_BUILD
#Preview { RemoteView() }
#endif
