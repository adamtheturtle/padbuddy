import Foundation

extension WidgetSync {
    typealias PadCandidate = (id: String, pad: Pad)

    /// Keep only the newest rows. For duplicate IDs, the newest occurrence wins.
    static func newestPads(from pads: [Pad], limit: Int) -> [PadCandidate] {
        guard limit > 0 else { return [] }

        var selected: [PadCandidate] = []
        for pad in pads {
            guard pad.id.utf8.count <= 256, let id = PadIDValidation.normalize(pad.id) else { continue }

            let candidate = (id: id, pad: pad)
            if let duplicate = selected.firstIndex(where: { $0.id == id }) {
                guard precedes(candidate, selected[duplicate]) else { continue }

                selected.remove(at: duplicate)
            }
            let insertion = selected.firstIndex { precedes(candidate, $0) } ?? selected.endIndex
            guard insertion < limit else { continue }

            selected.insert(candidate, at: insertion)
            if selected.count > limit {
                selected.removeLast()
            }
        }
        return selected
    }

    private static func precedes(_ lhs: PadCandidate, _ rhs: PadCandidate) -> Bool {
        let left = lhs.pad.updatedAt ?? lhs.pad.createdAt ?? .distantPast
        let right = rhs.pad.updatedAt ?? rhs.pad.createdAt ?? .distantPast
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
