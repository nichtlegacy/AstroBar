// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AstroBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AstroBarCore", targets: ["AstroBarCore"]),
        .executable(name: "AstroBar", targets: ["AstroBar"]),
        .executable(name: "astrobar-cli", targets: ["AstroBarCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure logic + IOKit HID transport. No UI. Unit-testable.
        .target(
            name: "AstroBarCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // Debug/diagnostic CLI: dumps every value the base station exposes.
        .executableTarget(
            name: "AstroBarCLI",
            dependencies: ["AstroBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // The menu bar app.
        .executableTarget(
            name: "AstroBar",
            dependencies: [
                "AstroBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // Not `resources:`. SwiftPM would generate a resource bundle whose
            // accessor only looks next to `Bundle.main.bundleURL` — the .app
            // root, where nothing may live without breaking the code signature —
            // and otherwise falls back to the absolute .build path of the
            // machine that compiled it. A downloaded copy would find neither.
            // The icon ships loose in Contents/Resources like any other Mac app,
            // and nothing here reads resources through `Bundle.module`.
            exclude: ["Resources"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                // Sparkle ships as a dynamic framework that package_app.sh copies
                // into Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]),
        .testTarget(
            name: "AstroBarCoreTests",
            dependencies: ["AstroBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "AstroBarUITests",
            dependencies: ["AstroBar", "AstroBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
    ])
