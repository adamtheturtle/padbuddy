//
//  SpotlightIndexer+Fingerprints.swift
//  coderpad
//

import Foundation

extension SpotlightIndexer {
    nonisolated struct PadIndexRecord {
        let identifier: String
        let title: String
        let description: String
        var fingerprint: Int {
            contentFingerprint(title, description)
        }
    }

    nonisolated struct QuestionIndexRecord {
        let identifier: String
        let title: String
        let description: String
        var fingerprint: Int {
            contentFingerprint(title, description)
        }
    }

    nonisolated static func changedPadRecords(_ records: [PadIndexRecord]) -> [PadIndexRecord] {
        enrichmentLock.withLock { records.filter { indexedPadFingerprints[$0.identifier] != $0.fingerprint } }
    }

    nonisolated static func changedQuestionRecords(_ records: [QuestionIndexRecord]) -> [QuestionIndexRecord] {
        enrichmentLock.withLock { records.filter { indexedQuestionFingerprints[$0.identifier] != $0.fingerprint } }
    }

    nonisolated static func acknowledgePadRecords(
        _ records: [PadIndexRecord], generation: Int? = nil, account: UUID? = nil
    ) {
        enrichmentLock.withLock {
            if let generation, let account {
                guard isCurrentIndexStateLocked(generation: generation, account: account) else { return }
            }

            for record in records {
                indexedPadFingerprints[record.identifier] = record.fingerprint
            }
        }
    }

    nonisolated static func acknowledgeQuestionRecords(
        _ records: [QuestionIndexRecord], generation: Int? = nil, account: UUID? = nil
    ) {
        enrichmentLock.withLock {
            if let generation, let account {
                guard isCurrentIndexStateLocked(generation: generation, account: account) else { return }
            }

            for record in records {
                indexedQuestionFingerprints[record.identifier] = record.fingerprint
            }
        }
    }

    nonisolated static func removeBaseFingerprints(account: UUID) {
        let padAccountPrefix = "\(padPrefix)\(account.uuidString):"
        let questionAccountPrefix = "\(questionPrefix)\(account.uuidString):"
        indexedPadFingerprints = indexedPadFingerprints.filter { !$0.key.hasPrefix(padAccountPrefix) }
        indexedQuestionFingerprints = indexedQuestionFingerprints.filter { !$0.key.hasPrefix(questionAccountPrefix) }
    }

    private nonisolated static func contentFingerprint(_ values: String...) -> Int {
        var hasher = Hasher()
        for value in values {
            hasher.combine(value)
        }
        return hasher.finalize()
    }
}
