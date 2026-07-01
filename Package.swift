// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NoSleep", targets: ["NoSleep"])
    ],
    targets: [
        .executableTarget(
            name: "NoSleep",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
