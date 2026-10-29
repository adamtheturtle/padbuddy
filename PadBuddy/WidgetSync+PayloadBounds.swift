import Foundation

extension WidgetSync {
    typealias PadCandidate = (id: String, pad: Pad)

    /// Keep only the newest rows. For duplicate IDs, the newest occurrence wins.
    static func newestPads(from pads: [Pad], limit: Int, now: Date = .now) -> [PadCandidate] {
        guard limit > 0 else { return [] }

        var selected: [PadCandidate] = []
        for pad in pads {
            guard let id = WidgetSharedStore.validatedHandoffPadID(pad.id),
                  PadIDValidation.normalize(id) == id else { continue }

            let candidate = (id: id, pad: pad)
            if let duplicate = selected.firstIndex(where: { $0.id == id }) {
                guard precedes(candidate, selected[duplicate], now: now) else { continue }

                selected.remove(at: duplicate)
            }
            let insertion = selected.firstIndex { precedes(candidate, $0, now: now) } ?? selected.endIndex
            guard insertion < limit else { continue }

            selected.insert(candidate, at: insertion)
            if selected.count > limit {
                selected.removeLast()
            }
        }
        return selected
    }

    static func snapshotDate(for pad: Pad, now: Date) -> Date? {
        WidgetSharedStore.plausibleTimestamp(pad.updatedAt, now: now)
            ?? WidgetSharedStore.plausibleTimestamp(pad.createdAt, now: now)
    }

    private static func precedes(_ lhs: PadCandidate, _ rhs: PadCandidate, now: Date) -> Bool {
        let left = snapshotDate(for: lhs.pad, now: now) ?? .distantPast
        let right = snapshotDate(for: rhs.pad, now: now) ?? .distantPast
        return left == right ? lhs.id < rhs.id : left > right
    }

    static let maximumIndexedAccounts = 256

    static func accountIndex(_ accounts: [Account]) -> [WidgetAccount] {
        accounts.prefix(maximumIndexedAccounts).map { account in
            let identifier = WidgetAccountIdentity.identifier(for: account)
            let name = ExternalText.singleLine(account.name, limit: 128)
            return WidgetAccount(
                id: identifier, name: name.isEmpty ? String(identifier.prefix(8)) : name,
                legacyID: account.id.uuidString
            )
        }
    }
}
