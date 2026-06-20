// swift-tools-version: 6.2
import PackageDescription

/// The app's generic, domain-free SwiftUI design-system primitives — colour tokens,
/// spacing, and the small reusable views (cards, section headers, stat tiles, chips,
/// avatars) — extracted from the coderpad app so they can be shared with the
/// HackerRank app (#377). Settings mirror the app target so the source compiles
/// identically here: Swift 6 language mode and MainActor default actor isolation.
let package = Package(
    name: "CoderPadDesignSystem",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoderPadDesignSystem", targets: ["CoderPadDesignSystem"])
    ],
    dependencies: [
        // Backs the reusable `FlowLayout` wrapper (#391/#377). Pinned to the same
        // major the app uses so the two resolve to one Flow version.
        .package(url: "https://github.com/tevelee/SwiftUI-Flow", from: "3.4.0"),
        // Backs the reusable `MarkdownText` view (#377). Pinned to the exact version
        // the app uses so the two resolve to one Textual revision.
        .package(url: "https://github.com/adamtheturtle/textual", exact: "0.3.1-coderpad.2")
    ],
    targets: [
        .target(
            name: "CoderPadDesignSystem",
            dependencies: [
                .product(name: "Flow", package: "SwiftUI-Flow"),
                .product(name: "Textual", package: "textual")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                // Mirror the app target's SWIFT_APPROACHABLE_CONCURRENCY = YES.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "CoderPadDesignSystemTests",
            dependencies: ["CoderPadDesignSystem"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        )
    ]
)
