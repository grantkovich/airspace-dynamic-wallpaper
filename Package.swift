// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Airspace",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Airspace", targets: ["Airspace"]),
    ],
    targets: [
        .target(name: "AirspaceCore"),
        .executableTarget(name: "Airspace", dependencies: ["AirspaceCore"]),
        .testTarget(
            name: "AirspaceCoreTests",
            dependencies: ["AirspaceCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
