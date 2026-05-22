// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Lumina", targets: ["PhotoViewer"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PhotoViewer",
            dependencies: [],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"])
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        )
    ]
)
