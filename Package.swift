// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ListPP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ListPP", targets: ["ListPP"])
    ],
    targets: [
        .executableTarget(name: "ListPP")
    ]
)
