//
//  coderpadTests+PadCacheMutations.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad cache mutations")
struct PadCacheMutationTests {
    @Test func `only the newest cache persistence epoch remains current`() {
        let epochs = CachePersistenceEpochs()
        let account = UUID()
        let otherAccount = UUID()
        let stale = epochs.advance(for: account)
        let current = epochs.advance(for: account)
        let other = epochs.advance(for: otherAccount)

        #expect(!epochs.isCurrent(stale, for: account))
        #expect(epochs.isCurrent(current, for: account))
        #expect(epochs.isCurrent(other, for: otherAccount))
        #expect(!epochs.isCurrent(current, for: otherAccount))
    }

    @Test func `question disk hydration publishes each identity once`() async throws {
        let question = try await CoderPadClient.mock(key: "cache-normalization-\(UUID().uuidString)")
            .getQuestion(id: 102)

        #expect(QuestionsCacheStore.normalizedDiskQuestions([question, question]) == [question])
    }

    @Test func `disk hydration keeps the first row for each pad identity`() {
        let first = Pad(id: "pad", title: "First")
        let duplicate = Pad(id: "pad", title: "Duplicate")
        let other = Pad(id: "other", title: "Other")

        #expect(PadsCacheStore.normalizedDiskPads([first, duplicate, other, duplicate]) == [first, other])
    }

    @Test func `fresh detail replaces every duplicate cached row`() {
        let stale = Pad(id: "pad", title: "Stale")
        let fresh = Pad(id: "pad", title: "Fresh")
        let updated = PadCacheMutation.replacing(fresh, in: [stale, stale])
        #expect(updated == [fresh, fresh])
    }

    @Test func `unchanged and absent authoritative lists do not rewrite`() {
        let pad = Pad(id: "pad", title: "Current")
        #expect(PadCacheMutation.replacing(pad, in: [pad]) == nil)
        #expect(PadCacheMutation.replacing(pad, in: []) == nil)
    }

    @Test func `a directly reached pad appends to an existing list`() {
        let existing = Pad(id: "one", title: "One")
        let direct = Pad(id: "two", title: "Two")
        #expect(PadCacheMutation.replacing(direct, in: [existing]) == [existing, direct])
    }

    @Test @MainActor
    func `question deletion requires the current account client identity`() throws {
        let account = Account(name: "Deletion provenance", apiKey: "current-\(UUID().uuidString)")
        AccountsStore.shared.add(account)
        defer { AccountsStore.shared.remove(id: account.id) }
        let data = try JSONSerialization.data(withJSONObject: ["id": 72901, "title": "Question"])
        let question = try CoderPadClient.decoder.decode(Question.self, from: data)
        QuestionsCacheStore.shared.set(account.id, questions: [question], via: account.makeClient())
        var staleAccount = account
        staleAccount.apiKey = "stale-key"

        let rejected = QuestionsCacheStore.shared.removeQuestion(
            id: question.id, account: account.id, via: staleAccount.makeClient().taskIdentity
        )
        #expect(!rejected)
        #expect(QuestionsCacheStore.shared.cached(account.id) == [question])

        let accepted = QuestionsCacheStore.shared.removeQuestion(
            id: question.id, account: account.id, via: account.makeClient().taskIdentity
        )
        #expect(accepted)
        #expect(QuestionsCacheStore.shared.cached(account.id).isEmpty)
    }

    @Test @MainActor
    func `newer question cache load rejects an older completion from the same client`() throws {
        let account = Account(name: "Question load ordering", apiKey: "load-\(UUID().uuidString)")
        AccountsStore.shared.add(account)
        defer { AccountsStore.shared.remove(id: account.id) }
        let client = account.makeClient()
        let older = try #require(QuestionsCacheStore.shared.beginLoad(account.id, via: client))
        let newer = try #require(QuestionsCacheStore.shared.beginLoad(account.id, via: client))
        let oldQuestion = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id": 72902, "title": "Old"}"#.utf8)
        )
        let newQuestion = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id": 72903, "title": "New"}"#.utf8)
        )

        QuestionsCacheStore.shared.set(
            account.id, questions: [newQuestion], via: client, persist: false, accepting: newer
        )
        QuestionsCacheStore.shared.set(
            account.id, questions: [oldQuestion], via: client, persist: false, accepting: older
        )

        #expect(QuestionsCacheStore.shared.cached(account.id) == [newQuestion])
    }

    @Test @MainActor
    func `direct question mutation invalidates an in-flight list load`() throws {
        let account = Account(name: "Question mutation ordering", apiKey: "mutation-\(UUID().uuidString)")
        AccountsStore.shared.add(account)
        defer { AccountsStore.shared.remove(id: account.id) }
        let client = account.makeClient()
        let load = try #require(QuestionsCacheStore.shared.beginLoad(account.id, via: client))
        let mutation = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id": 72904, "title": "Mutation"}"#.utf8)
        )
        let stale = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id": 72905, "title": "Stale load"}"#.utf8)
        )

        QuestionsCacheStore.shared.set(account.id, questions: [mutation], via: client, persist: false)
        QuestionsCacheStore.shared.set(
            account.id, questions: [stale], via: client, persist: false, accepting: load
        )

        #expect(QuestionsCacheStore.shared.cached(account.id) == [mutation])
    }

    @Test @MainActor
    func `pad deletion requires the current account client identity`() {
        let account = Account(name: "Pad deletion provenance", apiKey: "current-\(UUID().uuidString)")
        AccountsStore.shared.add(account)
        defer { AccountsStore.shared.remove(id: account.id) }
        let pad = Pad(id: "pad-\(UUID().uuidString)", title: "Pad")
        PadsCacheStore.shared.set(account.id, pads: [pad], via: account.makeClient())
        var staleAccount = account
        staleAccount.apiKey = "stale-key"

        let rejected = PadsCacheStore.shared.removePad(
            id: pad.id, account: account.id, via: staleAccount.makeClient().taskIdentity
        )
        #expect(!rejected)
        #expect(PadsCacheStore.shared.cached(account.id) == [pad])

        let accepted = PadsCacheStore.shared.removePad(
            id: pad.id, account: account.id, via: account.makeClient().taskIdentity
        )
        #expect(accepted)
        #expect(PadsCacheStore.shared.cached(account.id).isEmpty)
    }
}
