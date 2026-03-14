// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusMenu",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "StatusMenu", targets: ["StatusMenuApp"]),
    ],
    targets: [
        .executableTarget(
            name: "StatusMenuApp",
            path: "Sources/StatusMenuApp"
        ),
    ]
)

