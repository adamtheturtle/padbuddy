import Foundation

extension DockBadgeController {
    /// Reject oversized identities before trimming or case normalization.
    static func canonicalBadgeEmail(_ raw: String) -> String? {
        guard raw.utf8.count <= 512 else { return nil }

        let email = raw.canonicalOwnerEmail
        guard !email.isEmpty, email.utf8.count <= 254 else { return nil }

        return email
    }
}
