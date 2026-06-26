//
//  Exports.swift
//  CoderPadMCPCore
//
//  The pad/question count-aggregate-compact and get_pad_code transforms moved to the
//  shared CoderPadToolCore package (#521) so the in-app `--mcp` server reuses the exact
//  same functions. The generic MCP scaffolding (argument coercion, the descriptor->Tool
//  bridge, result builders, prompt helpers, and the server bootstrap) moved to buddy-kit's
//  BuddyMCP (#565). Re-exporting both keeps the executable and the tests calling the
//  transforms and the generic helpers unqualified, as before the moves.
//

@_exported import BuddyMCP
@_exported import CoderPadToolCore
