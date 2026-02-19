// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nami",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Nami", targets: ["Nami"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0")
    ],
    targets: [
        .systemLibrary(
            name: "NamiBridge",
            path: "Sources/NamiBridge"
        ),
        .executableTarget(
            name: "Nami",
            dependencies: [
                "NamiBridge",
                "KeyboardShortcuts",
                "Yams"
            ],
            path: "Sources/Nami"
        )
    ]
)
