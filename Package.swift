// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadsetGuard",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "HeadsetGuard", targets: ["HeadsetGuard"]),
        .library(name: "HeadsetGuardKit", targets: ["HeadsetGuardKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HeadsetGuardKit",
            dependencies: [],
            path: "Sources/HeadsetGuardKit",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "HeadsetGuard",
            dependencies: ["HeadsetGuardKit"],
            path: "Sources/HeadsetGuard",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .testTarget(
            name: "HeadsetGuardKitTests",
            dependencies: ["HeadsetGuardKit"],
            path: "Tests/HeadsetGuardKitTests",
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-Xfrontend", "-disable-cross-import-overlays"])
            ],
            linkerSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
