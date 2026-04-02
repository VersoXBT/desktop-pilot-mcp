// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DesktopPilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "desktop-pilot-mcp", targets: ["DesktopPilotCLI"]),
        .library(name: "DesktopPilot", targets: ["DesktopPilot"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DesktopPilot",
            dependencies: [],
            path: "Sources/DesktopPilot",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "DesktopPilotCLI",
            dependencies: ["DesktopPilot"],
            path: "Sources/DesktopPilotCLI"
        ),
        .testTarget(
            name: "DesktopPilotTests",
            dependencies: ["DesktopPilot"],
            path: "Tests/DesktopPilotTests"
        )
    ]
)
