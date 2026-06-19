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
    targets: [
        .target(
            name: "CoderPadDesignSystem",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                // Mirror the app target's SWIFT_APPROACHABLE_CONCURRENCY = YES.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        )
    ]
)
