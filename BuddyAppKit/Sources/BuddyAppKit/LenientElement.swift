//
//  LenientElement.swift
//  BuddyAppKit
//

import Foundation

/// Wraps a decodable element so a per-element decode failure yields `nil` instead of
/// aborting the whole array — letting a loader drop an individual invalid element
/// while keeping the rest.
public struct LenientElement<Wrapped: Decodable>: Decodable {
    public let value: Wrapped?

    public init(from decoder: any Decoder) {
        value = try? decoder.singleValueContainer().decode(Wrapped.self)
    }
}
