//
//  WidgetHandoffRequests.swift
//  coderpad
//
//  CoderPad-owned validation, legacy migration, and routing adapters around AppGroupMailbox.
//

import AppGroupMailbox
import Foundation
import OSLog

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
                    messageLifetime: 24 * 60 * 60,
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

        do {
            let request = WidgetNewPadRequest(account: owner, question: owner == nil ? nil : seed, id: requestID)
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

        do {
            let claims = try mailbox.claimPending()
            let excess = max(0, claims.count - maxDrainedRequests)
            for claim in claims.prefix(excess) {
                try? claim.acknowledge()
            }

            var seenNewPadIDs = Set<UUID>()
            return claims.suffix(maxDrainedRequests).compactMap { claim in
                if case let .newPad(request) = claim.message,
                   !seenNewPadIDs.insert(request.id).inserted {
                    try? claim.acknowledge()
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

    static func claimedRequestOriginalName(_ fileName: String) -> String? {
        originalName(in: fileName, prefix: legacyClaimPrefix)
    }

    static func abandonedClaimOriginalName(fileName: String, age: TimeInterval) -> String? {
        guard age > abandonedClaimLifetime else { return nil }

        return claimedRequestOriginalName(fileName)
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
        if let kind = isNewPadRequest(fileName: name) {
            return LegacyCandidate(source: url, originalName: name, isNewPad: kind)
        }
        if let original = claimedRequestOriginalName(name) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard Date().timeIntervalSince(modified ?? Date()) > abandonedClaimLifetime else { return nil }

            return LegacyCandidate(
                source: url,
                originalName: original,
                isNewPad: isNewPadRequest(fileName: original) == true
            )
        }
        if let original = originalName(in: name, prefix: legacyImportPrefix) {
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

        let request: WidgetPendingRequest? = if candidate.isNewPad {
            (try? decoder.decode(WidgetNewPadRequest.self, from: data)).map(WidgetPendingRequest.newPad)
        } else {
            (try? decoder.decode(WidgetOpenPadRequest.self, from: data)).map(WidgetPendingRequest.openPad)
        }
        guard let request else {
            quarantineLegacyFile(claimed, in: container)
            return
        }

        do {
            try mailbox.enqueue(request, id: legacyMigrationID(fileName: candidate.originalName))
            try FileManager.default.removeItem(at: claimed)
        } catch {
            logger.error("""
            Could not import a legacy widget handoff request: \
            \(error.localizedDescription, privacy: .private)
            """)
        }
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

    private static func safeLegacyData(at url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (0 ... maxRequestFileBytes).contains(size) else { return nil }

        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func quarantineLegacyFile(_ url: URL, in container: URL) {
        let destination = container.appendingPathComponent(
            "\(legacyQuarantinePrefix)\(UUID().uuidString).bin",
            isDirectory: false
        )
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    private static func trimLegacyQuarantine(in container: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: nil
        ) else { return }

        let quarantined = urls
            .filter { $0.lastPathComponent.hasPrefix(legacyQuarantinePrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in quarantined.dropLast(20) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
