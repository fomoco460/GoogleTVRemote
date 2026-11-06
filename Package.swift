// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleTVRemote",
    platforms: [.iOS(.v17)],
    products: [.library(name: "GoogleTVRemote", targets: ["GoogleTVRemote"])],
    targets: [
        .target(
            name: "GoogleTVRemote",
            path: ".",
            exclude: ["Tests", "README.md", "LOCAL-BUILD.md", "project.yml", "xtool.yml", "Support"],
            sources: ["RemoteApp.swift", "TVConnection.swift", "BluetoothBackup.swift", "Identity.swift", "Wire.swift"],
            swiftSettings: [.define("XTOOL_BUILD")]
        )
    ],
    swiftLanguageModes: [.v5]
)
