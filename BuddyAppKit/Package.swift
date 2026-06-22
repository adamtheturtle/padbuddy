// swift-tools-version: 6.2
import PackageDescription

/// Zero-coupling app utilities extracted from the coderpad app (#511), the first and
/// lowest-risk step of the buddy-kit shared-foundation effort. Holds only
/// service-agnostic helpers (pasteboard, URL opening, reachability, a relative-date
/// cache, multi-selection rules, a serial write queue, and a lenient array decoder),
/// so a sibling app can share them unchanged. The settings mirror the app target so
/// the moved source compiles identically here: Swift 6 language mode and MainActor
/// default actor isolation, against which the files' `nonisolated` annotations are
/// written.
let package = Package(
    name: "BuddyAppKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BuddyAppKit", targets: ["BuddyAppKit"])
    ],
    targets: [
        .target(
            name: "BuddyAppKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                // Mirror the app target's SWIFT_APPROACHABLE_CONCURRENCY = YES so the
                // helpers run on the caller's actor (SE-0461) and compile here exactly
                // as they do in the app.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "BuddyAppKitTests",
            dependencies: ["BuddyAppKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        )
    ]
)
