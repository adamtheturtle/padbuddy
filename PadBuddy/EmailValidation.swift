import Foundation
import SwiftEmailValidator

nonisolated enum EmailValidation {
    static func isPlausibleAddress(_ value: String) -> Bool {
        EmailSyntaxValidator.correctlyFormatted(value) { domain in
            // The RFC-reserved example domains are used by previews and tests, while
            // all other domains retain the package's IANA deliverability policy.
            domain == "example.com" || domain.hasSuffix(".example.com")
                || TLDDomainValidator.isPubliclyDeliverable(domain)
        }
    }

    /// The address trimmed, with its case-insensitive domain lowercased, so the same
    /// mailbox entered with different casing stores and compares consistently
    /// (#1941). The local part's case is preserved: its semantics belong to the
    /// receiving server.
    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.lastIndex(of: "@") else { return trimmed }

        let domain = trimmed[trimmed.index(after: atIndex)...].lowercased()
        return "\(trimmed[..<atIndex])@\(domain)"
    }
}
