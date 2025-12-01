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
        .package(path: "../vapor-identity"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
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
