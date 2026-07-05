// swift-tools-version: 6.1
//
// The network-free, plumbing-neutral core of the CoderPad MCP tool set (#521): the
// pad/question count-aggregate-compact transforms and the get_pad_code assembly. Both
// MCP servers depend on this so a tool's data shaping is written once — the in-app
// `--mcp` server (#402) and the standalone `coderpad-mcp` CLI (#393), both wiring these
// transforms through the shared MCPKit seam. Foundation only, no MCP-SDK or app
// coupling, so either plumbing can wrap the same pure functions. A sibling of the app
// and of `CoderPadMCP` at the repo root.

import PackageDescription

let package = Package(
    name: "CoderPadToolCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CoderPadToolCore", targets: ["CoderPadToolCore"])
    ],
    targets: [
        .target(name: "CoderPadToolCore")
    ]
)
