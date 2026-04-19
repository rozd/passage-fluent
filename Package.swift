// swift-tools-version:6.0
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
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor-community/passage.git", from: "0.1.0"),
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
            ]
        )
    ]
)
