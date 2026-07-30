//
//  WriteSafety.swift
//  CoderPadMCPCore
//

import MCP

/// Parses the write safety flag without failing open. Absent is a valid live
/// request; a present value must be an actual boolean or the exact JSON-string
/// spelling used by older MCP clients.
public enum StrictDryRunValue: Equatable, Sendable {
    case absent
    case value(Bool)
    case invalid
}

public func strictDryRunArgument(_ arguments: [String: Value]?) -> StrictDryRunValue {
    guard let value = arguments?["dry_run"] else { return .absent }

    switch value {
    case let .bool(value):
        return .value(value)
    case .string("true"):
        return .value(true)
    case .string("false"):
        return .value(false)
    default:
        return .invalid
    }
}
