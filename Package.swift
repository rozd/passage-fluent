// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "vapor-identity-store-fluent",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "IdentityFluent", targets: ["IdentityFluent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rozd/vapor-identity.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
    ],
    targets: [
        .target(
            name: "IdentityFluent",
            dependencies: [
                .product(name: "Identity", package: "vapor-identity"),
                .product(name: "Fluent", package: "fluent"),
            ]
        ),
    ]
)
