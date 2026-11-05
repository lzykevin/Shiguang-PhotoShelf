// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoShelf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PhotoShelf", targets: ["PhotoShelf"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "PhotoLibraryCore"),
        .executableTarget(name: "PhotoShelf", dependencies: ["PhotoLibraryCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/Samples")]),
        .testTarget(name: "PhotoLibraryCoreTests", dependencies: ["PhotoLibraryCore"]),
        .testTarget(name: "PhotoShelfTests", dependencies: ["PhotoShelf", "PhotoLibraryCore"])
    ]
)
