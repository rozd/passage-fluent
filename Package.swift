// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "passage-fluent",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PassageFluent", targets: ["PassageFluent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rozd/passage.git", from: "0.0.1"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
    ],
    targets: [
        .target(
            name: "PassageFluent",
            dependencies: [
                .product(name: "Passage", package: "passage"),
                .product(name: "Fluent", package: "fluent"),
            ]
        ),
    ]
)
