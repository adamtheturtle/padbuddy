//
//  Arguments.swift
//  CoderPadMCPCore
//
//  Coercion helpers for tool-call arguments. MCP clients are loosely typed — a
//  numeric id can arrive as an int, a double, or a string — so these accept any
//  reasonable encoding rather than failing on a type mismatch.
//

import Foundation
import MCP

/// A string argument, coercing ints/doubles to their textual form. Returns nil when
/// the key is absent or holds a non-scalar value.
public func stringArgument(_ arguments: [String: Value]?, _ key: String) -> String? {
    switch arguments?[key] {
    case let .string(value): value
    case let .int(value): String(value)
    case let .double(value): String(value)
    default: nil
    }
}

/// An integer argument, coercing doubles (truncating) and numeric strings. Returns
/// nil when the key is absent or can't be read as an integer.
public func intArgument(_ arguments: [String: Value]?, _ key: String) -> Int? {
    switch arguments?[key] {
    case let .int(value): value
    case let .double(value): Int(value)
    case let .string(value): Int(value)
    default: nil
    }
}

/// A trimmed, non-empty string argument, or nil — so empty strings don't get sent as
/// real values in write bodies.
public func optionalString(_ arguments: [String: Value]?, _ key: String) -> String? {
    guard let value = stringArgument(arguments, key)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
    else { return nil }

    return value
}
