// swift-tools-version: 6.2
import PackageDescription

/// A generic, domain-free transport for paginated, bearer-authenticated REST APIs,
/// extracted from the coderpad app (#151). The settings mirror the app target so the
/// source compiles identically here: Swift 6 language mode and MainActor default actor
/// isolation, against which the file's `nonisolated` annotations are written.
let package = Package(
    name: "PaginatedRESTClient",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PaginatedRESTClient", targets: ["PaginatedRESTClient"])
    ],
    targets: [
        .target(
            name: "PaginatedRESTClient",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                // Mirror the app target's SWIFT_APPROACHABLE_CONCURRENCY = YES so the
                // file's `nonisolated` async methods run on the caller's actor (SE-0461)
                // and compile here exactly as they do in the app.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "PaginatedRESTClientTests",
            dependencies: ["PaginatedRESTClient"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                // Mirror the app target's SWIFT_APPROACHABLE_CONCURRENCY = YES so the
                // file's `nonisolated` async methods run on the caller's actor (SE-0461)
                // and compile here exactly as they do in the app.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        )
    ]
)
