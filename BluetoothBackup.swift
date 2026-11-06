import CoreBluetooth
import Combine
import Foundation

// Experimental HOGP peripheral. Requires physical iPhone/Chromecast validation.
// Uses public CoreBluetooth APIs and canonical Bluetooth SIG UUIDs.
final class BluetoothBackup: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published var enabled = false
    @Published private(set) var ready = false
    @Published private(set) var status = "Bluetooth backup off"
    private var manager: CBPeripheralManager?
    private var keyboard: CBMutableCharacteristic?
    private var consumer: CBMutableCharacteristic?
    private var host: CBCentral?
    private var queue: [(Data, CBMutableCharacteristic)] = []
    private var pairingAllowed = false
    private var subscriptions: Set<ObjectIdentifier> = []
    private var approvedID = UserDefaults.standard.string(forKey: "bluetoothTV")
    private static func uuid(_ short: String) -> CBUUID {
        CBUUID(string: "0000\(short)-0000-1000-8000-00805F9B34FB")
    }
    func startPairing() {
        enabled = true; pairingAllowed = true; ready = false
        status = "On the TV, open Settings → Remotes & accessories → Pair accessory"
        if manager == nil { manager = CBPeripheralManager(delegate: self, queue: .main) }
        else if manager?.state == .poweredOn { advertise() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.pairingAllowed = false }
    }
    func stop() {
        enabled = false; ready = false; pairingAllowed = false
        manager?.stopAdvertising(); manager?.removeAllServices(); manager = nil
        keyboard = nil; consumer = nil; host = nil; subscriptions.removeAll(); queue.removeAll()
        status = "Bluetooth backup off"
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        ready = false
        guard peripheral.state == .poweredOn else {
            status = "Bluetooth unavailable. Check Bluetooth permission and Settings."; return
        }
        let keyboardMap: [UInt8] = [
            0x05,0x01,0x09,0x06,0xa1,0x01,0x85,0x01, // keyboard, report 1
            0x05,0x07,0x19,0xe0,0x29,0xe7,0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x08,0x81,0x02,
            0x95,0x01,0x75,0x08,0x81,0x01,
            0x95,0x06,0x75,0x08,0x15,0x00,0x26,0xff,0x00,0x05,0x07,0x19,0x00,0x2a,0xff,0x00,0x81,0x00,0xc0,
            0x05,0x0c,0x09,0x01,0xa1,0x01,0x85,0x02, // consumer, report 2
            0x15,0x00,0x26,0xff,0x03,0x19,0x00,0x2a,0xff,0x03,0x75,0x10,0x95,0x01,0x81,0x00,0xc0]
        func constant(_ uuid: String, _ data: Data) -> CBMutableCharacteristic {
            CBMutableCharacteristic(type: Self.uuid(uuid), properties: [.read], value: data, permissions: [.readable])
        }
        func report(_ id: UInt8) -> CBMutableCharacteristic {
            let report = CBMutableCharacteristic(type: Self.uuid("2A4D"),
                properties: [.read, .notify, .notifyEncryptionRequired], value: nil,
                permissions: [.readable, .readEncryptionRequired])
            report.descriptors = [CBMutableDescriptor(type: Self.uuid("2908"), value: Data([id, 1]) as NSData)]
            return report
        }
        let keyboard = report(1), consumer = report(2)
        self.keyboard = keyboard; self.consumer = consumer
        let mode = CBMutableCharacteristic(type: Self.uuid("2A4E"), properties: [.read, .writeWithoutResponse], value: nil, permissions: [.readable, .writeable])
        let control = CBMutableCharacteristic(type: Self.uuid("2A4C"), properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: Self.uuid("1812"), primary: true)
        service.characteristics = [constant("2A4A", Data([0x11,0x01,0x00,0x02])),
            constant("2A4B", Data(keyboardMap)), mode, control, keyboard, consumer]
        peripheral.add(service)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { status = "Bluetooth HID rejected by iOS: \(error.localizedDescription)"; return }
        advertise()
    }
    private func advertise() {
        manager?.startAdvertising([CBAdvertisementDataLocalNameKey: "My TV Remote",
                                  CBAdvertisementDataServiceUUIDsKey: [Self.uuid("1812")]])
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didStartAdvertising error: Error?) {
        if let error { status = "Bluetooth advertising failed: \(error.localizedDescription)" }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard approvedID == central.identifier.uuidString || pairingAllowed,
              host == nil || host?.identifier == central.identifier else {
            status = "Unknown Bluetooth host ignored. Use Pair Bluetooth TV to authorize a new one."; return
        }
        approvedID = central.identifier.uuidString
        UserDefaults.standard.set(approvedID, forKey: "bluetoothTV")
        host = central; subscriptions.insert(ObjectIdentifier(characteristic))
        ready = true; status = "Bluetooth subscribed • test the direction buttons"
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard host?.identifier == central.identifier else { return }
        subscriptions.remove(ObjectIdentifier(characteristic))
        if subscriptions.isEmpty {
            ready = false; host = nil; queue.removeAll(); status = "Bluetooth disconnected"
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let bytes: Data
        if request.characteristic === keyboard { bytes = Data(repeating: 0, count: 8) }
        else if request.characteristic === consumer { bytes = Data([0, 0]) }
        else { bytes = Data([1]) }
        guard request.offset <= bytes.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
        request.value = Data(bytes.dropFirst(request.offset)); peripheral.respond(to: request, withResult: .success)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests { peripheral.respond(to: request, withResult: .success) }
    }
    @discardableResult func key(_ androidCode: UInt64) -> Bool {
        guard enabled, ready, queue.count < 30, let keyboard, let consumer else { return false }
        let keyboardCodes: [UInt64: UInt8] = [19: 0x52, 20: 0x51, 21: 0x50, 22: 0x4f, 23: 0x28, 66: 0x28, 4: 0x29]
        let consumerCodes: [UInt64: UInt16] = [3: 0x223, 24: 0xe9, 25: 0xea, 164: 0xe2, 85: 0xcd, 26: 0x30, 166: 0x9c, 167: 0x9d]
        if let code = keyboardCodes[androidCode], subscriptions.contains(ObjectIdentifier(keyboard)) {
            queue.append((Data([0,0,code,0,0,0,0,0]), keyboard))
            queue.append((Data(repeating: 0, count: 8), keyboard))
        } else if let code = consumerCodes[androidCode], subscriptions.contains(ObjectIdentifier(consumer)) {
            queue.append((Data([UInt8(code & 255), UInt8(code >> 8)]), consumer))
            queue.append((Data([0,0]), consumer))
        } else { status = "This button is unavailable over Bluetooth."; return false }
        drain(); return true
    }
    private func drain() {
        guard let manager, let host else { return }
        while let item = queue.first {
            guard manager.updateValue(item.0, for: item.1, onSubscribedCentrals: [host]) else { return }
            queue.removeFirst()
        }
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { drain() }
}
