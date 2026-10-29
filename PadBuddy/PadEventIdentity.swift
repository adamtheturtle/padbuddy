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
    /// A diagnostic identity built from bounded fields. The positional group
    /// prefix supplies uniqueness; playback uses this as a compact feed signature.
    /// Bound each field before composing so a large remote message is never copied
    /// in full just to derive a short view identity.
    var identity: String {
        let fields = [String(createdAt?.timeIntervalSince1970 ?? 0), kind, userName ?? "", message]
        return fields.map { field in
            String(field.unicodeScalars.prefix(64).map {
                CharacterSet.controlCharacters.contains($0) ? " " : Character($0)
            })
        }.joined(separator: "-")
    }
}
