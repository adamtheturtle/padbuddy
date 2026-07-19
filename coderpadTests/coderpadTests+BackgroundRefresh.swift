//
//  coderpadTests+BackgroundRefresh.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Background refresh snapshots")
@MainActor
struct BackgroundRefreshSnapshotTests {
    @Test
    func `a changed backend reseeds instead of returning its old snapshot`() {
        let accountID = UUID()
        let firstClient = ClientTaskIdentity(apiKey: "first", baseURL: URL.staticURL("https://example.com"))
        let secondClient = ClientTaskIdentity(apiKey: "second", baseURL: URL.staticURL("https://example.com"))
        let first = ["old": PadActivitySnapshot(updatedAt: nil, isEnded: false, participantCount: 1)]
        let second = ["new": PadActivitySnapshot(updatedAt: nil, isEnded: false, participantCount: 2)]
        var states: [UUID: PadsBackgroundRefresher.AccountActivityState] = [:]

        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: firstClient, snapshot: first, states: &states
        ) == nil)
        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: firstClient, snapshot: second, states: &states
        )?["old"]?.participantCount == 1)
        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: secondClient, snapshot: first, states: &states
        ) == nil)
        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: secondClient, snapshot: second, states: &states
        )?["old"]?.participantCount == 1)
    }
}
