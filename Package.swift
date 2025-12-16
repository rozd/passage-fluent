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
        .package(url: "https://github.com/vapor/vapor.git", from: "4.119.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor-community/passage.git", from: "0.0.9"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "PassageFluent",
            dependencies: [
                .product(name: "Passage", package: "passage"),
                .product(name: "Fluent", package: "fluent"),
            ]
        ),
        .testTarget(
            name: "PassageFluentTests",
            dependencies: [
                "PassageFluent",
                .product(name: "Passage", package: "passage"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Testing", package: "swift-testing"),
            ]
        )
    ]
)
