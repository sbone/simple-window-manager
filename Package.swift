// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OptimalLayout",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OptimalLayout", targets: ["OptimalLayout"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(
            name: "OptimalLayout",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "OLSmokeTest", path: "SmokeTests"),
        .testTarget(name: "OptimalLayoutTests", dependencies: ["OptimalLayout"])
    ]
)
