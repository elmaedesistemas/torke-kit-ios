// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TorkeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Measurement engine and session. Foundation only: runs on iOS, macOS and in tests.
        .library(name: "TorkeKit", targets: ["TorkeKit"]),
        // Phone sensors: CoreMotion at 100 Hz and CoreLocation at the GPS's top rate.
        .library(name: "TorkeKitSensors", targets: ["TorkeKitSensors"]),
        // TorkeKit's times against dragstrip timeslips, on the Mac: `swift run torke-validate --help`.
        .executable(name: "torke-validate", targets: ["torke-validate"]),
    ],
    targets: [
        .target(name: "TorkeKit"),
        .target(name: "TorkeKitSensors", dependencies: ["TorkeKit"]),
        .executableTarget(name: "torke-validate", dependencies: ["TorkeKit"]),
        .testTarget(
            name: "TorkeKitTests",
            dependencies: ["TorkeKit"],
            resources: [.copy("Resources")]
        ),
    ]
)
