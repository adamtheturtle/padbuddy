//
//  CommandPalette+Bounds.swift
//  coderpad
//

import Foundation

extension CommandPaletteBuilder {
    static let maximumPadResults = 200
    static let maximumQuestionResults = 200
    static let maximumNewPadResults = 100
    static let maximumAccountResults = 50

    static func uniqueQuestions(_ questions: [Question], limit: Int = .max) -> [Question] {
        guard limit > 0 else { return [] }

        var seen = Set<Int>()
        var result: [Question] = []
        result.reserveCapacity(min(limit, questions.count))
        for question in questions where seen.insert(question.id).inserted {
            result.append(question)
            if result.count == limit {
                break
            }
        }
        return result
    }

    static func uniquePads(_ pads: [Pad], limit: Int = .max) -> [Pad] {
        guard limit > 0 else { return [] }

        var seen = Set<String>()
        var result: [Pad] = []
        result.reserveCapacity(min(limit, pads.count))
        for pad in pads where seen.insert(pad.id).inserted {
            result.append(pad)
            if result.count == limit {
                break
            }
        }
        return result
    }

    static func uniqueAccounts(_ accounts: [Account], limit: Int = .max) -> [Account] {
        guard limit > 0 else { return [] }

        var seen = Set<UUID>()
        var result: [Account] = []
        result.reserveCapacity(min(limit, accounts.count))
        for account in accounts where seen.insert(account.id).inserted {
            result.append(account)
            if result.count == limit {
                break
            }
        }
        return result
    }

    /// Accounts offered as palette switch targets must be able to construct a
    /// supported client. This keeps incomplete re-keying drafts and malformed
    /// self-hosted URLs from switching the whole app into an unusable state.
    static func switchableAccounts(_ accounts: [Account], limit: Int = .max) -> [Account] {
        uniqueAccounts(accounts.filter(\.isUsableSyncedCredential), limit: limit)
    }
}
