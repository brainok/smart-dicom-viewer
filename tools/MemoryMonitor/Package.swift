// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MemoryMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MemoryMonitor", targets: ["MemoryMonitor"])
    ],
    targets: [
        .executableTarget(name: "MemoryMonitor")
    ]
)
