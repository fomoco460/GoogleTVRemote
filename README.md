# My TV Remote

Personal iPhone remote for Chromecast with Google TV 4K, with a dark circular directional pad inspired by the supplied reference.

## Build without a Mac

GitHub Actions generates the Xcode project, runs the simulator tests, and builds `MyTVRemote-unsigned.ipa`. Open Actions → Build iPhone app → latest successful run → Artifacts. The unsigned IPA must be signed and installed using an iOS sideloading tool on Windows; downloading it onto an iPhone alone does not install it. A TestFlight release requires Apple signing and App Store Connect setup separately.

## Connect

Allow Local Network access, keep the phone and Chromecast on the same network, and open the gear button. Select a discovered TV or enter its IP address. Connect, then enter the six-character code displayed on the television. Pairing uses a unique RSA identity stored in iOS Keychain. The television's public key is pinned after PIN verification. Reconnect reuses this identity; Pair again is available if the television has forgotten the phone.

Wi-Fi controls include navigation, OK, Home, Back, power, volume, mute, channel keys, play/pause, text entry, and app-link shortcuts. Power, channel, volume, text, and deep-link behavior depend on the television and foreground app. Volume keys cannot reproduce the physical remote's infrared emitter. Select a TV text field before sending keyboard text. Direct microphone audio streaming is not implemented; iPhone keyboard dictation can produce text to send.

## Experimental Bluetooth backup

In settings, select Pair Bluetooth TV, then find My TV Remote in the Chromecast's Remotes & accessories pairing menu. The app publishes a BLE HID keyboard and consumer-control service. Supported remote buttons fall back to Bluetooth when Wi-Fi is disconnected and the television has subscribed. This is experimental: iOS publication and Chromecast interoperability require physical-device validation. A subscription indicates transport readiness, not proof that the television handles every button. Keep the iPhone app in the foreground. Text and app shortcuts currently require Wi-Fi.

## Reliability

The network layer handles fragmented and coalesced length-prefixed protobuf frames, checks message sizes, replies to keepalives, detects idle sockets, and makes up to three reconnect attempts with backoff. Commands are not queued across disconnections, preventing delayed power toggles or navigation bursts.

## Development

No third-party runtime dependencies. Requires iOS 17+. `xcodegen generate` produces the Xcode project from project.yml. Tests exercise fragmented/coalesced frames, malformed protobuf, size limits, Unicode payloads, and persistent self-signed client identity creation. Hardware testing remains necessary after a successful build.

Protocol references used during implementation:
- https://github.com/tronikos/androidtvremote2
- https://github.com/odyshewroman/AndroidTVRemoteControl
- https://github.com/keefeere/InpuDeck (Bluetooth feasibility reference)

No upstream source files or shared pairing certificates are bundled in the app.
