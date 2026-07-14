// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CET6DesktopWidget",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "CET6DesktopWidget",
            targets: ["CET6DesktopWidget"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CET6DesktopWidget",
            path: "Sources/CET6DesktopWidget"
        ),
        .testTarget(
            name: "CET6DesktopWidgetTests",
            dependencies: ["CET6DesktopWidget"],
            path: "Tests/CET6DesktopWidgetTests"
        )
    ]
)
