// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Airspace",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Airspace", targets: ["Airspace"]),
    ],
    dependencies: [
        // Updates for the direct download. Pinned; SwiftPM checks the framework's checksum.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "AirspaceCore"),
        .executableTarget(
            name: "Airspace",
            dependencies: ["AirspaceCore", .product(name: "Sparkle", package: "Sparkle")],
            // The app bundle keeps Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "AirspaceCoreTests",
            dependencies: ["AirspaceCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
