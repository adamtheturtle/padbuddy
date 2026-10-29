import Foundation

extension DockBadgeController {
    /// Reject oversized identities before trimming or case normalization.
    static func canonicalBadgeEmail(_ raw: String) -> String? {
        guard raw.utf8.count <= 512 else { return nil }

        let email = raw.canonicalOwnerEmail
        guard !email.isEmpty, email.utf8.count <= 254 else { return nil }

        return email
    }

    /// Validate before hashing or retaining IDs. First record per ID still wins,
    /// including when an inactive record precedes an active duplicate.
    static func ownActivePadCount(_ pads: [Pad], ownerEmail: String) -> Int {
        var seen = Set<String>()
        return pads.count {
            guard let id = MergedPadIdentity.validated($0.id), seen.insert(id).inserted,
                  $0.status == .active else { return false }

            return canonicalBadgeEmail($0.ownerEmail) == ownerEmail
        }
    }
}
