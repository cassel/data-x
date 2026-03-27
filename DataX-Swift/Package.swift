// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DataX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DataX", targets: ["DataX"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DataX",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "DataX"
        ),
        .testTarget(
            name: "DataXTests",
            dependencies: [
                "DataX",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/DataXTests"
        )
    ]
)
