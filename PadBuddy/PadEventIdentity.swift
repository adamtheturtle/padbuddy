//
//  PadEventIdentity.swift
//  coderpad
//
//  The events feed has no server-supplied identifier, so the app derives one.
//
//  `PadEvent` used to carry this as an `Identifiable` `id`; CoderPadKit 0.5.14
//  dropped both without noting it in its changelog. The derivation is reproduced
//  verbatim so event grouping identities and the cached feed signatures keep
//  comparing exactly as before the bump.
//

import CoderPadKit
import Foundation

extension PadEvent {
    /// A composite identity for one event: its instant, kind, actor, and message.
    ///
    /// Not unique — two events can legitimately share all four (see the grouping
    /// rules in `PadEventGrouping`) — and not bounded, because `message` is
    /// server-provided and can be arbitrarily long and carry newlines and control
    /// characters. Callers that put it in a view identity go through
    /// `PadEventGrouping.identitySuffix(for:)`, which normalizes and caps it.
    var identity: String {
        "\(createdAt?.timeIntervalSince1970 ?? 0)-\(kind)-\(userName ?? "")-\(message)"
    }
}
