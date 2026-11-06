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
    private let background = Color(white: 0.115)
    private let rim = LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        GeometryReader { geometry in
            let padSize = min(geometry.size.width - 32, geometry.size.height * 0.49)
            VStack(spacing: 0) {
                Button { settings = true } label: {
                    HStack(spacing: 10) {
                        Circle().fill(tv.connected || bluetooth.ready ? .green : .gray).frame(width: 8, height: 8)
                        Text(tv.connected ? tv.displayName : "Choose TV").font(.system(size: 25, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                }
                .padding(.top, 12)
                HStack {
                    Button { settings = true } label: { Image(systemName: "gearshape.fill") }
                    Spacer()
                    Button { command(.power) } label: { Image(systemName: "power").foregroundStyle(.red) }
                }
                .font(.system(size: 28)).padding(.horizontal, 30).padding(.top, 20)
                Spacer(minLength: 16)
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(white: 0.2), background], startPoint: .top, endPoint: .bottom))
                    Circle().stroke(rim, lineWidth: 2)
                    direction("chevron.up", .up).offset(y: -padSize * 0.325)
                    direction("chevron.down", .down).offset(y: padSize * 0.325)
                    direction("chevron.left", .left).offset(x: -padSize * 0.325)
                    direction("chevron.right", .right).offset(x: padSize * 0.325)
                    Button { command(.select) } label: {
                        Circle().fill(Color(white: 0.19))
                            .overlay(Circle().stroke(rim, lineWidth: 3))
                            .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
                    }.frame(width: padSize * 0.29, height: padSize * 0.29)
                        .accessibilityLabel("OK")
                }.frame(width: padSize, height: padSize)
                Spacer(minLength: 18)
                Text(!tv.connected && bluetooth.ready ? "Bluetooth backup • experimental" : (tv.error ?? tv.status)).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).padding(.bottom, 18)
                HStack(spacing: 12) {
                    rocker(tv.muted ? "MUTE" : "VOL", top: "plus", bottom: "minus", first: .volumeUp, second: .volumeDown, blue: true,
                           level: tv.muted ? 0 : tv.volume.map { Double($0) / 100 })
                    VStack(spacing: 16) {
                        HStack(spacing: 10) {
                            utility("keyboard", label: "Keyboard") { keyboard = true }
                            utility("house", label: "Home") { command(.home) }
                            utility("circle.grid.3x3.fill", label: "Apps") { apps = true }
                        }
                        HStack(spacing: 10) {
                            utility(tv.muted ? "speaker.slash.fill" : "speaker.wave.2", label: "Mute") { command(.mute) }
                            utility("playpause.fill", label: "Play or pause") { sendKey(85) }
                            utility("arrow.uturn.backward", label: "Back") { command(.back) }
                        }
                    }
                    rocker("CH", top: "chevron.up", bottom: "chevron.down", first: .channelUp, second: .channelDown, blue: false)
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(Color(white: 0.84)).buttonStyle(.plain)
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
            }.onAppear { discovery.start() }.onDisappear { discovery.stop() }
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
            }.presentationDetents([.medium])
        }
        .confirmationDialog("App shortcuts", isPresented: $apps, titleVisibility: .visible) {
            Button("YouTube") { tv.launch("https://www.youtube.com") }
            Button("Netflix") { tv.launch("https://www.netflix.com") }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear { if tv.host.isEmpty { settings = true } else { tv.connect() } }
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

    private func direction(_ symbol: String, _ value: RemoteCommand) -> some View {
        Button { command(value) } label: {
            Image(systemName: symbol).font(.system(size: 27, weight: .semibold))
                .frame(width: 64, height: 64).contentShape(Rectangle())
        }.accessibilityLabel(value.rawValue)
    }

    private func utility(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(Color(white: 0.19))
                .overlay(Image(systemName: symbol).font(.system(size: 25, weight: .regular)))
                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        }.accessibilityLabel(label)
    }

    private func rocker(_ title: String, top: String, bottom: String, first: RemoteCommand, second: RemoteCommand, blue: Bool, level: Double? = nil) -> some View {
        VStack(spacing: 0) {
            Button { command(first) } label: {
                Image(systemName: top).font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }.accessibilityLabel(blue ? "Volume up" : "Channel up")
            Text(title).font(.system(size: 15, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7).padding(.vertical, 8)
            Button { command(second) } label: {
                Image(systemName: bottom).font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }.accessibilityLabel(blue ? "Volume down" : "Channel down")
        }.frame(width: 56, height: 172)
            .background {
                ZStack(alignment: .bottom) {
                    Capsule().fill(blue ? Color(red: 0.12, green: 0.26, blue: 0.36) : Color(white: 0.19))
                    if blue {
                        // Fill rises with the TV's volume percentage.
                        Rectangle().fill(Color(red: 0.22, green: 0.50, blue: 0.70))
                            .frame(height: 172 * (level ?? 1))
                            .animation(.easeOut(duration: 0.2), value: level)
                    }
                }.clipShape(Capsule())
            }
    }
}

#if !XTOOL_BUILD
#Preview { RemoteView() }
#endif
