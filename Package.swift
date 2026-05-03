// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacFanCore", targets: ["MacFanCore"]),
        .executable(name: "MacFanApp", targets: ["MacFanApp"]),
        .executable(name: "MacFanHelper", targets: ["MacFanHelper"])
    ],
    targets: [
        .target(name: "MacFanCore"),
        .executableTarget(
            name: "MacFanApp",
            dependencies: ["MacFanCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "MacFanHelper",
            dependencies: ["MacFanCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "MacFanCoreTests",
            dependencies: ["MacFanCore"],
            swiftSettings: [.unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])],
            linkerSettings: [.unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib", "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"])]
        )
    ]
)
