// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AIQuotaWatch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIQuotaWatch", targets: ["AIQuotaWatch"])
    ],
    targets: [
        .executableTarget(name: "AIQuotaWatch")
    ]
)
