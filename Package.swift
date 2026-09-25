// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v27)
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
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
