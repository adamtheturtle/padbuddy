//
//  WidgetHandoffRequests.swift
//  coderpad
//
//  CoderPad-owned validation, legacy migration, and routing adapters around AppGroupMailbox.
//

// swiftlint:disable file_length

import AppGroupMailbox
import Foundation
import OSLog
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

nonisolated extension WidgetSharedStore {
    private struct LegacyCandidate {
        let source: URL
        let originalName: String
        let isNewPad: Bool
    }

    static let maxPendingRequests = 100
    static let maxRequestFileBytes = 65536
    static let maxDrainedRequests = 10
    static let abandonedClaimLifetime: TimeInterval = 10 * 60
    static let legacyRequestLifetime: TimeInterval = 24 * 60 * 60
    static let handoffRequestNotification = "\(appGroupID).handoff-request-enqueued"

    private static let mailboxNamespace = "widget-actions"
    private static let legacyClaimPrefix = "claimed-"
    private static let legacyImportPrefix = "legacy-import-"
    private static let legacyQuarantinePrefix = "legacy-quarantine-"
    private static let legacyNewPadFile = "pending-new-pad.json"
    private static let legacyOpenPadFile = "pending-open-pad.json"
    private static let legacyNewPadPrefix = "pending-new-pad-"
    private static let legacyOpenPadPrefix = "pending-open-pad-"

    private static func handoffMailbox() -> AppGroupMailbox<WidgetPendingRequest>? {
        guard let container = containerURL(purpose: "widget handoff mailbox") else { return nil }

        return handoffMailbox(containerURL: container)
    }

    static func handoffMailbox(containerURL: URL) -> AppGroupMailbox<WidgetPendingRequest>? {
        do {
            return try AppGroupMailbox(
                containerURL: containerURL,
                namespace: mailboxNamespace,
                limits: .init(
                    maxMessages: maxPendingRequests,
                    maxPayloadBytes: maxRequestFileBytes,
                    messageLifetime: legacyRequestLifetime,
                    claimTimeout: abandonedClaimLifetime,
                    maxQuarantinedFiles: 20
                ),
                overflowPolicy: .discardOldest,
                notificationName: handoffRequestNotification
            )
        } catch {
            logger.error("Could not open the widget handoff mailbox: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    static var maxHandoffPadIDLength: Int {
        64
    }

    static func validatedHandoffPadID(_ id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... maxHandoffPadIDLength).contains(trimmed.count),
              trimmed.allSatisfy({ character in
                  character == "-" || character == "_"
                      || (character.isASCII && (character.isLetter || character.isNumber))
              }) else { return nil }

        return trimmed
    }

    static func validatedAccount(_ account: String?) -> String?? {
        guard let account else { return .some(nil) }

        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .some(nil)
        }
        if let uuid = UUID(uuidString: trimmed) {
            return .some(uuid.uuidString)
        }
        guard trimmed.count == 64, trimmed.allSatisfy(\.isHexDigit) else { return nil }

        return .some(trimmed.lowercased())
    }

    @discardableResult
    static func requestNewPad(account: String?, question: Int?, requestID: UUID = UUID()) -> Bool {
        let seed = question.flatMap { $0 > 0 ? $0 : nil }
        if question != nil, seed == nil {
            logger.error("Dropped a non-positive question seed from a new pad handoff request")
        }
        guard let owner = validatedAccount(account) else {
            logger.error("Refused a new pad handoff request with a malformed account identifier")
            return false
        }
        guard let mailbox = handoffMailbox() else { return false }

        // A question id is account-scoped, so seeding one against an unknown account could
        // open a different organization's question. Dropping it silently opened a blank pad
        // instead, with nothing to tell the user their configured question was ignored
        // (#4556); refusing the request lets the caller report it.
        guard owner != nil || seed == nil else {
            logger.error("Refused a new pad handoff request that seeds a question with no account")
            return false
        }

        do {
            let request = WidgetNewPadRequest(account: owner, question: seed, id: requestID)
            try mailbox.enqueue(.newPad(request), id: requestID)
            return true
        } catch {
            logger.error("""
            Could not enqueue a new pad handoff request: \
            \(error.localizedDescription, privacy: .private)
            """)
            return false
        }
    }

    @discardableResult
    static func requestOpenPad(id: String, account: String?) -> Bool {
        guard let padID = validatedHandoffPadID(id) else {
            logger.error("Refused an open pad handoff request with an empty or malformed pad id")
            return false
        }
        guard let owner = validatedAccount(account) else {
            logger.error("Refused an open pad handoff request with a malformed account identifier")
            return false
        }
        guard let mailbox = handoffMailbox() else { return false }

        do {
            try mailbox.enqueue(.openPad(WidgetOpenPadRequest(id: padID, account: owner)))
            return true
        } catch {
            logger.error("""
            Could not enqueue an open pad handoff request: \
            \(error.localizedDescription, privacy: .private)
            """)
            return false
        }
    }

    static func takePendingRequestsInOrder() -> [WidgetClaimedRequest] {
        migrateLegacyRequests()
        guard let mailbox = handoffMailbox() else { return [] }

        return takePendingRequestsInOrder(from: mailbox)
    }

    static func takePendingRequestsInOrder(
        from mailbox: AppGroupMailbox<WidgetPendingRequest>
    ) -> [WidgetClaimedRequest] {
        do {
            let claims = try mailbox.claimPending(limit: maxDrainedRequests)
            var seenNewPadIDs = Set<UUID>()
            return claims.compactMap { claim in
                if case let .newPad(request) = claim.message,
                   !seenNewPadIDs.insert(request.id).inserted {
                    if let failure = acknowledgementFailure(
                        context: "Could not acknowledge a duplicate new-pad widget handoff request",
                        acknowledge: claim.acknowledge
                    ) {
                        logger.error("\(failure, privacy: .private)")
                    }
                    return nil
                }
                return WidgetClaimedRequest(request: claim.message, claim: claim)
            }
        } catch {
            logger.error("Could not claim widget handoff requests: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    static func discardPendingRequests(account: String) {
        let owner = validatedAccount(account).flatMap(\.self)
        guard let owner else { return }

        migrateLegacyRequests()
        guard let mailbox = handoffMailbox(), let claims = try? mailbox.claimPending() else { return }

        for claim in claims {
            let named: String? = switch claim.message {
            case let .newPad(request): request.account
            case let .openPad(request): request.account
            }
            if named == owner {
                try? claim.acknowledge()
            } else {
                try? claim.release()
            }
        }
    }

    static func deduplicatingNewPadRequests(_ requests: [WidgetPendingRequest]) -> [WidgetPendingRequest] {
        var seen = Set<UUID>()
        return requests.filter { request in
            guard case let .newPad(newPad) = request else { return true }

            return seen.insert(newPad.id).inserted
        }
    }

    // MARK: - Legacy transport migration

    static func isNewPadRequest(fileName: String) -> Bool? {
        if fileName == legacyNewPadFile {
            return true
        }
        if fileName == legacyOpenPadFile {
            return false
        }
        guard fileName.hasSuffix(".json") else { return nil }

        if fileName.hasPrefix(legacyNewPadPrefix) {
            return true
        }
        if fileName.hasPrefix(legacyOpenPadPrefix) {
            return false
        }
        return nil
    }

    static func requestOrdinal(fileName: String) -> UInt64 {
        let remainder: Substring
        if fileName.hasPrefix(legacyNewPadPrefix) {
            remainder = fileName.dropFirst(legacyNewPadPrefix.count)
        } else if fileName.hasPrefix(legacyOpenPadPrefix) {
            remainder = fileName.dropFirst(legacyOpenPadPrefix.count)
        } else {
            return 0
        }
        return UInt64(remainder.prefix(while: \.isNumber)) ?? 0
    }

    /// How far ahead of wall time a legacy handoff mtime may be before it is treated
    /// as corrupt rather than ordinary clock skew (#4645).
    static let futureModificationTolerance: TimeInterval = 5 * 60

    static func claimedRequestOriginalName(_ fileName: String) -> String? {
        originalName(in: fileName, prefix: legacyClaimPrefix)
    }

    static func abandonedClaimOriginalName(fileName: String, age: TimeInterval) -> String? {
        guard age > abandonedClaimLifetime else { return nil }

        return claimedRequestOriginalName(fileName)
    }

    static func legacyRequestIsExpired(modifiedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(modifiedAt)
        // A far-future mtime yields a negative age and would otherwise remain eligible
        // until wall time catches up — potentially for years (#4645).
        if age < -futureModificationTolerance {
            return true
        }
        return age > legacyRequestLifetime
    }

    /// The UUID stamped into a claimed legacy filename, which is the migration id for
    /// that file. Hashing the *original* name instead gave both fixed singleton names
    /// (`pending-new-pad.json`, `pending-open-pad.json`) one permanent id, so a genuine
    /// later request under the same name was rejected as already imported and vanished
    /// (#4551). The claim name is stable across retries, so retrying still de-duplicates.
    static func legacyMigrationID(claimedFileName: String) -> UUID? {
        guard claimedFileName.hasPrefix(legacyImportPrefix) else { return nil }

        return UUID(uuidString: String(claimedFileName.dropFirst(legacyImportPrefix.count).prefix(36)))
    }

    static func legacyMigrationID(fileName: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 1_099_511_628_211
        for byte in fileName.utf8 {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte)) &* 14_029_467_366_897_019_727
        }
        let hex = String(format: "%016llx%016llx", first, second)
        let text = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-"
            + "a\(hex.dropFirst(17).prefix(3))-\(hex.suffix(12))"
        guard let identifier = UUID(uuidString: text) else {
            assertionFailure("The fixed-width migration hash must form a UUID")
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        }

        return identifier
    }

    private static func originalName(in fileName: String, prefix: String) -> String? {
        guard fileName.hasPrefix(prefix) else { return nil }

        let remainder = fileName.dropFirst(prefix.count)
        guard remainder.count > 37,
              UUID(uuidString: String(remainder.prefix(36))) != nil,
              remainder.dropFirst(36).first == "-" else { return nil }

        let original = String(remainder.dropFirst(37))
        return isNewPadRequest(fileName: original) == nil ? nil : original
    }

    private static func migrateLegacyRequests() {
        guard let container = containerURL(purpose: "legacy widget handoff migration"),
              let mailbox = handoffMailbox(containerURL: container) else { return }

        migrateLegacyRequests(in: container, mailbox: mailbox)
    }

    static func migrateLegacyRequests(
        in container: URL,
        mailbox: AppGroupMailbox<WidgetPendingRequest>
    ) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) else { return }

        let ordered = urls.compactMap { legacyCandidate(for: $0, in: container) }.sorted {
            (requestOrdinal(fileName: $0.originalName), $0.originalName)
                < (requestOrdinal(fileName: $1.originalName), $1.originalName)
        }

        for candidate in ordered {
            importLegacyCandidate(candidate, into: mailbox, in: container)
        }
        trimLegacyQuarantine(in: container)
    }

    private static func legacyCandidate(for url: URL, in container: URL) -> LegacyCandidate? {
        let name = url.lastPathComponent
        let pendingKind = isNewPadRequest(fileName: name)
        let claimedOriginal = claimedRequestOriginalName(name)
        let importingOriginal = originalName(in: name, prefix: legacyImportPrefix)
        if pendingKind != nil || claimedOriginal != nil || importingOriginal != nil {
            guard let modified = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate else {
                quarantineLegacyFile(url, in: container)
                return nil
            }

            if legacyRequestIsExpired(modifiedAt: modified) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    logger.error("Could not remove an expired legacy widget handoff: \(error)")
                }
                return nil
            }
        }
        if let kind = pendingKind {
            return LegacyCandidate(source: url, originalName: name, isNewPad: kind)
        }
        if let original = claimedOriginal {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard Date().timeIntervalSince(modified ?? Date()) > abandonedClaimLifetime else { return nil }

            return LegacyCandidate(
                source: url,
                originalName: original,
                isNewPad: isNewPadRequest(fileName: original) == true
            )
        }
        if let original = importingOriginal {
            return LegacyCandidate(
                source: url,
                originalName: original,
                isNewPad: isNewPadRequest(fileName: original) == true
            )
        }
        if name.hasPrefix(legacyClaimPrefix) || name.hasPrefix(legacyImportPrefix) {
            quarantineLegacyFile(url, in: container)
        }
        return nil
    }

    private static func importLegacyCandidate(
        _ candidate: LegacyCandidate,
        into mailbox: AppGroupMailbox<WidgetPendingRequest>,
        in container: URL
    ) {
        let claimed = claimLegacyCandidate(candidate, in: container)
        guard let claimed, let data = safeLegacyData(at: claimed) else {
            if let claimed {
                quarantineLegacyFile(claimed, in: container)
            }
            return
        }

        let request = validatedLegacyRequest(from: data, isNewPad: candidate.isNewPad)
        guard let request else {
            quarantineLegacyFile(claimed, in: container)
            return
        }

        // The claim's own UUID, so two files written under the same singleton name do not
        // share one migration id (#4551).
        let migrationID = legacyMigrationID(claimedFileName: claimed.lastPathComponent)
            ?? legacyMigrationID(fileName: candidate.originalName)
        do {
            try mailbox.enqueue(request, id: migrationID)
        } catch {
            logger.error("""
            Could not import a legacy widget handoff request: \
            \(error.localizedDescription, privacy: .private)
            """)
            return
        }

        // Enqueue and cleanup are separate: the message is in the mailbox now, so a
        // failed removal must not leave the file to be imported a second time once the
        // mailbox no longer holds the id to de-duplicate against (#4552).
        do {
            try FileManager.default.removeItem(at: claimed)
        } catch {
            logger.error("""
            Quarantining an imported legacy widget handoff whose source could not be removed: \
            \(error.localizedDescription, privacy: .private)
            """)
            quarantineLegacyFile(claimed, in: container)
        }
    }

    /// Decodes a legacy payload through the same validation the current writers apply.
    /// Migration used to enqueue anything that decoded, so account identifiers, pad ids,
    /// and question ids that `requestNewPad`/`requestOpenPad` would reject reached routing
    /// from the shared container unchecked (#4553, #4554, #4555).
    static func validatedLegacyRequest(from data: Data, isNewPad: Bool) -> WidgetPendingRequest? {
        if isNewPad {
            guard let decoded = try? decoder.decode(WidgetNewPadRequest.self, from: data),
                  let owner = validatedAccount(decoded.account) else { return nil }

            let seed = decoded.question.flatMap { $0 > 0 ? $0 : nil }
            if decoded.question != nil, seed == nil {
                logger.error("Dropped a non-positive question seed from a migrated new pad handoff")
                return nil
            }
            guard owner != nil || seed == nil else {
                logger.error("Refused a migrated new pad handoff that seeds a question with no account")
                return nil
            }

            return .newPad(WidgetNewPadRequest(account: owner, question: seed, id: decoded.id))
        }

        guard let decoded = try? decoder.decode(WidgetOpenPadRequest.self, from: data),
              let padID = validatedHandoffPadID(decoded.id),
              let owner = validatedAccount(decoded.account) else { return nil }

        return .openPad(WidgetOpenPadRequest(id: padID, account: owner))
    }

    private static func claimLegacyCandidate(_ candidate: LegacyCandidate, in container: URL) -> URL? {
        if candidate.source.lastPathComponent.hasPrefix(legacyImportPrefix) {
            return candidate.source
        }
        let claimed = container.appendingPathComponent(
            "\(legacyImportPrefix)\(UUID().uuidString)-\(candidate.originalName)",
            isDirectory: false
        )
        guard (try? FileManager.default.moveItem(at: candidate.source, to: claimed)) != nil else { return nil }

        return claimed
    }

    static func safeLegacyData(at url: URL, afterOpen: () -> Void = {}) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= maxRequestFileBytes else { return nil }

        afterOpen()

        var data = Data()
        while data.count <= maxRequestFileBytes {
            let remaining = maxRequestFileBytes + 1 - data.count
            let chunk: Data
            do {
                guard let read = try handle.read(upToCount: min(16 * 1024, remaining)),
                      !read.isEmpty else { break }

                chunk = read
            } catch {
                return nil
            }
            data.append(chunk)
        }
        return data.count <= maxRequestFileBytes ? data : nil
    }

    private static func quarantineLegacyFile(_ url: URL, in container: URL) {
        let destination = container.appendingPathComponent(
            "\(legacyQuarantinePrefix)\(UUID().uuidString).bin",
            isDirectory: false
        )
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    static func trimLegacyQuarantine(in container: URL, limit: Int = 20) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
        ) else { return }

        let quarantined = urls
            .filter { $0.lastPathComponent.hasPrefix(legacyQuarantinePrefix) }
            .map { url in (url, legacyQuarantineDate(url) ?? .distantPast) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }
                return lhs.0.lastPathComponent < rhs.0.lastPathComponent
            }
        for (url, _) in quarantined.prefix(max(0, quarantined.count - max(0, limit))) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func legacyQuarantineDate(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) else {
            return nil
        }

        let date = values.contentModificationDate ?? values.creationDate
        guard let date, date.timeIntervalSinceReferenceDate.isFinite else { return nil }

        return date
    }
}
