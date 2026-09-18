// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppleAgentKit",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0")
    ],
    products: [
        .library(
            name: "AppleAgentKit",
            targets: ["AppleAgentKit"]
        )
    ],
    targets: [
        .target(
            name: "AppleAgentKit"
        )
    ]
)
