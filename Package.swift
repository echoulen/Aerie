// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aerie",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aerie", targets: ["Aerie"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/ibrahimcetin/SwiftGitX.git", from: "0.4.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.17.0"),
    ],
    targets: [
        .executableTarget(
            name: "Aerie",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftGitX", package: "SwiftGitX"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            exclude: ["Resources/Info.plist"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AerieTests",
            dependencies: [
                "Aerie",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
