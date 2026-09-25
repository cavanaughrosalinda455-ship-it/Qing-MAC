// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QingMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QingMac", targets: ["QingMac"])],
    targets: [.executableTarget(name: "QingMac", path: "Sources/QingMac")]
)
