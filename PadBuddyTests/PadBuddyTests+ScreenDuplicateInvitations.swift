import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen duplicate invitation policy")
struct ScreenDuplicateInvitationTests {
    @Test
    func `untouched policy omits the wire field while explicit choices preserve booleans`() throws {
        for policy in ScreenInvitationDuplicatePolicy.allCases {
            let invitation = ScreenInvitation(candidateEmail: "candidate@example.com",
                                              allowDuplicateInvitations: policy.allowDuplicateInvitations)
            let data = try JSONEncoder().encode(invitation)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            switch policy {
            case .serviceDefault:
                #expect(body.keys.sorted() == ["candidate_email"])

            case .prevent:
                #expect(body["allow_duplicate_invitations"] as? Bool == false)

            case .allow:
                #expect(body["allow_duplicate_invitations"] as? Bool == true)
            }
        }
    }

    @Test
    func `preventing duplicates keeps an existing session and account scope intact`() async throws {
        let first = ScreenClient.mock(key: "duplicate-policy-first-" + UUID().uuidString)
        let second = ScreenClient.mock(key: "duplicate-policy-second-" + UUID().uuidString)
        let email = "duplicate@example.com"
        let original = try await first.sendInvitation(campaignID: 102, ScreenInvitation(candidateEmail: email))
        do {
            let invitation = ScreenInvitation(candidateEmail: email, allowDuplicateInvitations: false)
            _ = try await first.sendInvitation(campaignID: 102, invitation)
            Issue.record("Duplicate invitation was accepted")
        } catch let error as CoderPadError {
            #expect(error.errorDescription?.contains("Candidate already invited") == true)
        }
        let sessions = try await first.listAllTests(campaignID: 102)
        #expect(sessions.filter { $0.candidateEmail == email }.map(\.id) == [original.id].compactMap(\.self))
        let prevented = ScreenInvitation(candidateEmail: email, allowDuplicateInvitations: false)
        let independent = try await second.sendInvitation(campaignID: 102, prevented)
        #expect(independent.id != nil)
        let repeated = ScreenInvitation(candidateEmail: email, allowDuplicateInvitations: true)
        let allowed = try await first.sendInvitation(campaignID: 102, repeated)
        #expect(allowed.id != original.id)
    }

    #if os(macOS)
        @Test @MainActor
        func `invitation sheet renders the localized policy control`() throws {
            let campaign = try ScreenCampaign(id: 102, name: "Backend")
            let renderer = ImageRenderer(content: ScreenInviteSheet(client: .mock(key: "duplicate-policy-render"),
                                                                    campaign: campaign, onSent: {}))
            let image = try #require(renderer.nsImage)
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    #endif
}
