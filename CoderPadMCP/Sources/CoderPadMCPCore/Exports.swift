//
//  Exports.swift
//  CoderPadMCPCore
//
//  The pad/question count-aggregate-compact and get_pad_code transforms moved to the
//  shared CoderPadToolCore package (#521) so the in-app `--mcp` server reuses the exact
//  same functions. Re-exporting them keeps the executable and the CoderPadMCPCore tests
//  calling the transforms unqualified, as before the move.
//

@_exported import CoderPadToolCore
