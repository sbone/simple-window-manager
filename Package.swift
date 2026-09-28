// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OptimalLayout",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OptimalLayout", targets: ["OptimalLayout"])],
    targets: [
        .executableTarget(name: "OptimalLayout"),
        .executableTarget(name: "OLSmokeTest", path: "SmokeTests"),
        .testTarget(name: "OptimalLayoutTests", dependencies: ["OptimalLayout"])
    ]
)
