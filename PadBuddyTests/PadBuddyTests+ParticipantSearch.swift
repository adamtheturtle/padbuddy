//
//  PadBuddyTests+ParticipantSearch.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Participant display-name search")
struct ParticipantDisplayNameSearchTests {
    @Test
    func `search resolves participant identities through the directory`() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "pad-1",
            "title": "Interview",
            "state": "started",
            "owner_email": "owner@example.com",
            "participants": ["participant@example.com"]
        ])
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: data)
        let display: (String) -> String = { identity in
            identity == "participant@example.com" ? "Jane Smith" : identity
        }

        let result = PadListLogic.filter([pad], using: PadFilterCriteria(search: "smith"), display: display)

        #expect(result.map(\.id) == ["pad-1"])
    }
}
