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
    targets: [
        .executableTarget(
            name: "DataX",
            path: "DataX"
        ),
        .testTarget(
            name: "DataXTests",
            dependencies: ["DataX"],
            path: "Tests/DataXTests"
        )
    ]
)
