// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Freeloader",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Explorer", targets: ["NuFinder"])], // Fork: el ejecutable de pruebas también se llama Explorer
    targets: [
        .executableTarget(
            name: "NuFinder",
            path: "Sources/NuFinder"
        ),
        .testTarget(
            name: "NuFinderTests",
            dependencies: ["NuFinder"],
            path: "Tests/NuFinderTests"
        )
    ]
)
