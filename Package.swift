// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacThermalWatch",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "macthermalwatch", targets: ["MacThermalWatch"])
    ],
    targets: [
        .target(name: "MacThermalWatchCore"),
        .executableTarget(
            name: "MacThermalWatch",
            dependencies: ["MacThermalWatchCore"]
        ),
        .testTarget(
            name: "MacThermalWatchCoreTests",
            dependencies: ["MacThermalWatchCore"]
        )
    ]
)
