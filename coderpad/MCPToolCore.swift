//
//  MCPToolCore.swift
//  coderpad
//
//  Re-exports the shared CoderPadToolCore package (#521) so the in-app MCP server's
//  files (MCPTools+PadQuery / +QuestionQuery / +Tools) and their tests call the
//  pad/question count-aggregate-compact and get_pad_code transforms unqualified, with
//  no per-file import — the same umbrella pattern DesignSystem.swift uses for
//  CoderPadDesignSystem. The transforms used to live in app-local MCPPadAggregation /
//  MCPPadCode / MCPQuestionAggregation, byte-identical to the standalone CLI's copies;
//  they now live once in CoderPadToolCore and both servers depend on it.
//

#if os(macOS)
    @_exported import CoderPadMCP
#endif
