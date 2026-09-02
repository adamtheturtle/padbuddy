import Foundation
import Security

/// Whether a companion Keychain `SecItemDelete` left no credential behind (#4659).
/// `errSecItemNotFound` is success: nothing remains to erase.
nonisolated func companionKeychainDeletionSucceeded(_ status: OSStatus) -> Bool {
    status == errSecSuccess || status == errSecItemNotFound
}

#if !os(watchOS) && !os(tvOS)
    struct CompanionProvisioningIdentity: Equatable {
        let accountID: UUID
        let clientIdentity: ClientTaskIdentity

        init(account: Account) {
            accountID = account.id
            clientIdentity = account.makeClient().taskIdentity
        }
    }

    func companionStatusBelongsToAccount(
        statusIdentity: CompanionProvisioningIdentity?,
        account: Account
    ) -> Bool {
        statusIdentity == CompanionProvisioningIdentity(account: account)
    }
#endif

func companionSuccessIsStale(isSuccess: Bool, isAvailable: Bool) -> Bool {
    isSuccess && !isAvailable
}

/// The largest value in the cyclic provisioning serial-number space. Ordering uses
/// half-range arithmetic so rollover is newer while delayed pre-rollover payloads are
/// still older (#5168).
nonisolated let maxProvisioningRevision = UInt64(Int64.max)

nonisolated func nextWatchProvisioningRevision(after stored: UInt64?) -> UInt64 {
    let previous = stored.flatMap { $0 < maxProvisioningRevision ? $0 : nil } ?? 0
    return previous + 1
}

func shouldApplyWatchProvisioningRevision(_ incoming: UInt64?, latest: UInt64?) -> Bool {
    // An implausible stored revision is ignored, so provisioning can recover.
    let trustedLatest = latest.flatMap { (1 ... maxProvisioningRevision).contains($0) ? $0 : nil }
    guard let incoming else { return trustedLatest == nil }
    guard (1 ... maxProvisioningRevision).contains(incoming) else { return false }
    guard let trustedLatest else { return true }
    guard incoming != trustedLatest else { return false }

    let forwardDistance = if incoming > trustedLatest {
        incoming - trustedLatest
    } else {
        (maxProvisioningRevision - trustedLatest) + incoming
    }
    return forwardDistance <= maxProvisioningRevision / 2
}

/// How a provisioning payload's `revision` field parsed.
///
/// A missing revision means a legacy sender and is accepted when nothing newer has been
/// applied. A present-but-unparseable one is a malformed payload — conflating the two
/// meant malformed input was accepted as legacy, or silently ignored while the reply
/// still said `ok` (#4653).
nonisolated enum ProvisioningRevisionField: Equatable {
    case absent
    case value(UInt64)
    case invalid
}

nonisolated func parseProvisioningRevision(_ raw: Any?) -> ProvisioningRevisionField {
    guard let raw else { return .absent }
    guard let text = raw as? String, let value = UInt64(text), value <= maxProvisioningRevision else {
        return .invalid
    }

    return .value(value)
}

nonisolated enum WatchProvisioningReplyError: String {
    case invalidPayload = "invalid_payload"
    case saveFailed = "save_failed"
}

nonisolated struct TVProvisioningRequest: Equatable {
    private static let serverKey = "server"
    private static let apiKeyKey = "apiKey"
    private static let revisionKey = "revision"

    let server: URL
    let apiKey: String
    let revision: UInt64?

    init?(dictionary: [String: Any]) {
        guard let serverText = dictionary[Self.serverKey] as? String,
              let key = dictionary[Self.apiKeyKey] as? String else { return nil }

        let revision: UInt64?
        switch parseProvisioningRevision(dictionary[Self.revisionKey]) {
        case .absent: revision = nil
        case let .value(value): revision = value
        // Refused outright rather than treated as a legacy payload (#4653).
        case .invalid: return nil
        }
        self.init(serverText: serverText, apiKey: key, revision: revision)
    }

    private init?(serverText: String, apiKey keyText: String, revision: UInt64? = nil) {
        guard let candidate = URL(string: serverText), let server = Self.validatedServer(candidate) else { return nil }
        guard let key = Self.validatedAPIKey(keyText) else { return nil }

        self.server = server
        apiKey = key
        self.revision = revision
    }

    static func payload(server: URL, apiKey: String, revision: UInt64? = nil) -> [String: String]? {
        guard let server = validatedServer(server), let apiKey = validatedAPIKey(apiKey) else { return nil }

        var payload = [
            serverKey: server.absoluteString,
            apiKeyKey: apiKey
        ]
        if let revision {
            payload[revisionKey] = String(revision)
        }
        return payload
    }

    static func validatedAPIKey(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUnsafeScalar = value.unicodeScalars.contains {
            let category = $0.properties.generalCategory
            return category == .control || category == .format
        }
        return value.isEmpty || value.utf8.count > 4096 || hasUnsafeScalar ? nil : value
    }

    private static func validatedServer(_ server: URL) -> URL? {
        guard server.scheme?.lowercased() == "https", server.host != nil,
              server.user == nil, server.password == nil, server.query == nil,
              server.fragment == nil else { return nil }

        return server
    }

    /// Re-check a value loaded from defaults before treating the companion as
    /// provisioned — older builds or corrupted restores can persist `http:` or
    /// credential-bearing URLs (#4655).
    static func validatedPersistedServer(_ server: URL) -> URL? {
        validatedServer(server)
    }
}

#if os(iOS)
    extension TVProvisioningRequest {
        static func payload(for account: Account, revision: UInt64? = nil) -> [String: String]? {
            guard !account.isMock else { return nil }
            guard !account.hasMalformedBaseURLOverride else { return nil }

            return payload(server: account.resolvedBaseURL, apiKey: account.apiKey, revision: revision)
        }
    }
#endif
