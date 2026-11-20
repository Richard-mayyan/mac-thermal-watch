// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacThermalWatch",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "macthermalwatch", targets: ["MacThermalWatch"]),
        .executable(name: "MacThermalWatchApp", targets: ["MacThermalWatchApp"])
    ],
    targets: [
        .target(name: "MacThermalWatchCore"),
        .executableTarget(
            name: "MacThermalWatch",
            dependencies: ["MacThermalWatchCore"]
        ),
        .executableTarget(
            name: "MacThermalWatchApp",
            dependencies: ["MacThermalWatchCore"]
        ),
        .testTarget(
            name: "MacThermalWatchCoreTests",
            dependencies: ["MacThermalWatchCore"]
        )
    ]
)
