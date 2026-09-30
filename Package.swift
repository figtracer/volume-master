// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VolumeMaster",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "VolumeMaster", targets: ["VolumeMaster"])],
    targets: [
        .target(name: "VolumeDSP", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
        .executableTarget(name: "VolumeMaster", dependencies: ["VolumeDSP"]),
        .executableTarget(name: "VolumeCheck", dependencies: ["VolumeDSP"], path: "Tests/VolumeDSPTests")
    ]
)
