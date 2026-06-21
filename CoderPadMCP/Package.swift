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
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        // The network-free core (argument coercion, tool schemas, and the pad
        // code/count/aggregate transforms), split out so it can be unit-tested (#522).
        .target(
            name: "CoderPadMCPCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
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
