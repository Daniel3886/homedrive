// swift-tools-version:6.0
import PackageDescription

var targets: [Target] = [
    .target(name: "HomeDriveCore"),
    .testTarget(name: "HomeDriveCoreTests", dependencies: ["HomeDriveCore"]),
]
var products: [Product] = [
    .library(name: "HomeDriveCore", targets: ["HomeDriveCore"]),
]

// The SwiftUI app only builds on macOS. The core library (and its tests) also
// build on Linux, which lets CI exercise the GNU find/tar code paths.
#if os(macOS)
targets.append(.executableTarget(name: "HomeDrive", dependencies: ["HomeDriveCore"]))
products.append(.executable(name: "HomeDrive", targets: ["HomeDrive"]))
#endif

let package = Package(
    name: "HomeDrive",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v5]
)
