// swift-tools-version: 6.2
import PackageDescription

/// The reusable, Foundation-only core of the in-app Model Context Protocol server
/// (#514, part of the buddy-kit extraction). Owns the stdio run loop, the JSON-RPC 2.0
/// envelope and dispatch, and the account directory; the app-specific tool catalogue is
/// injected through the ``MCPToolProvider`` seam, so a sibling app can reuse the whole
/// server by supplying its own tools. No REST or app dependency. Settings mirror the app
/// target so the moved source compiles identically: Swift 6 language mode and MainActor
/// default isolation, against which the files' `nonisolated` annotations are written.
let package = Package(
    name: "BuddyMCP",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BuddyMCP", targets: ["BuddyMCP"])
    ],
    targets: [
        .target(
            name: "BuddyMCP",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "BuddyMCPTests",
            dependencies: ["BuddyMCP"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        )
    ]
)
