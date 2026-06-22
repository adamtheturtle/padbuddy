// swift-tools-version: 6.1
//
// A standalone local MCP server that exposes a CoderPad account's pads and
// questions to MCP-aware tools (Claude, editors, etc). Kept as its own package
// at the repo root — a sibling of the app and of `PaginatedRESTClient` — so it
// builds and runs on its own (`swift run coderpad-mcp`) without touching the
// macOS app target. See README.md for setup (#393).

import PackageDescription

let package = Package(
    name: "CoderPadMCP",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        // The plumbing-neutral pad/question transforms now live in a shared package the
        // in-app server depends on too (#521), so the data shaping is defined once.
        .package(path: "../CoderPadToolCore")
    ],
    targets: [
        // The MCP-bound core (argument coercion, tool schemas, prompts/resources), split
        // out so it can be unit-tested (#522). Re-exports CoderPadToolCore so the
        // executable and tests keep calling the transforms unqualified.
        .target(
            name: "CoderPadMCPCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                "CoderPadToolCore"
            ]
        ),
        .executableTarget(
            name: "coderpad-mcp",
            dependencies: [
                "CoderPadMCPCore",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "CoderPadMCPCoreTests",
            dependencies: ["CoderPadMCPCore"]
        )
    ]
)
