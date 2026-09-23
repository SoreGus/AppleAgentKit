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
    dependencies: [
        .package(
            url: "https://github.com/huggingface/swift-huggingface.git",
            from: "0.10.1"
        )
    ],
    targets: [
        .target(
            name: "AppleAgentKit",
            dependencies: [
                .product(
                    name: "HuggingFace",
                    package: "swift-huggingface"
                )
            ]
        )
    ]
)
