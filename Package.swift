// swift-tools-version: 5.9
import PackageDescription
import Foundation
let edition = ProcessInfo.processInfo.environment["AKITO_EDITION"] ?? "public"
precondition(edition == "public", "This sanitized source builds Public only")
let editionFlags: [SwiftSetting] = [.define("AKITO_PUBLIC")]
let package = Package(name: "AkitoStation", platforms: [.macOS(.v14)], products: [.library(name: "AkitoStationCore", targets: ["AkitoStationCore"]), .library(name: "RetroHost", targets: ["RetroHost"]), .executable(name: "AkitoStation", targets: ["AkitoStation"])], targets: [
.target(name: "RetroHost", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("dl")]),
.target(name: "RuntimeSupport", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("z")]),
.target(name: "AkitoStationCore", dependencies: ["RuntimeSupport"]),
.executableTarget(name: "AkitoStation", dependencies: ["AkitoStationCore", "RetroHost"], swiftSettings: editionFlags, linkerSettings: [.linkedFramework("MetalKit"), .linkedFramework("GameController"), .linkedFramework("AVFoundation")]),
.testTarget(name: "AkitoStationCoreTests", dependencies: ["AkitoStationCore"])
])
