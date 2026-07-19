//
//  coderpadTests+ScreenDemo.swift
//  coderpadTests
//
//  Drives the app's in-process demo Screen API (MockScreen + MockScreenFixtures) the
//  way the Screen UI does, so the demo data the Screen views render — campaigns, test
//  sessions across every status, scored reports with a technology/skill breakdown, and
//  the unauthorized (bad-key) path — stays correct. Unlike `ScreenClientTests` (which
//  uses a test-local mock purely to verify decoding), this exercises the *shipped*
//  demo fixtures end to end, the same path the Demo account hits (#314/#442). Each test
//  uses a unique state key so write paths don't leak into the others.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen demo data (MockScreen fixtures)")
struct ScreenDemoDataTests {
    @Test
    func `the demo serves five campaigns, including the pinned and archived ones`() async throws {
        let campaigns = try await ScreenClient.mock(key: "demo-campaigns").listCampaigns()
        #expect(campaigns.count == 5)
        let byID = Dictionary(uniqueKeysWithValues: campaigns.map { ($0.id, $0) })
        #expect(byID[101]?.name == "Backend Engineer")
        #expect(byID[101]?.pinned == true)
        #expect(byID[101]?.languages.contains("python3") == true)
        #expect(byID[105]?.archived == true)
    }

    @Test
    func `a campaign's demo sessions span every status with a scored report`() async throws {
        let tests = try await ScreenClient.mock(key: "demo-tests").listAllTests(campaignID: 101)
        #expect(tests.count == 5)
        #expect(Set(tests.map(\.status)) == ["completed", "in_progress", "waiting", "aborted"])
        let ada = tests.first { $0.candidateName == "Ada Lovelace" }
        #expect(ada?.status == "completed")
        #expect(ada?.report?.score == 88)
    }

    @Test
    func `the demo honors the from date bound so the Date Range picker works (#999)`() async throws {
        let client = ScreenClient.mock(key: "demo-tests-from")
        let all = try await client.listAllTests(campaignID: 101)
        #expect(all.count == 5)

        // Campaign 101's fixture activity ages are ~0.2, 0.5, 5, 8, and 11 days:
        // "Last 7 days" must drop the two older sessions.
        let sevenDaysAgo = Int(Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970 * 1000)
        let recent = try await client.listAllTests(campaignID: 101, from: sevenDaysAgo)
        #expect(recent.count == 3)
        #expect(recent.allSatisfy { ($0.lastActivityTime ?? 0) >= sevenDaysAgo })
    }

    @Test
    func `a completed demo session decodes its report with technologies and skills`() async throws {
        let detail = try await ScreenClient.mock(key: "demo-report").getTest(id: 5001)
        #expect(detail.report?.score == 88)
        let technologies = detail.report?.technologies ?? [:]
        #expect(technologies["Java"] != nil)
        #expect(technologies["Algorithms"]?.skills.isEmpty == false)
    }

    @Test
    func `the seed sessions are built once and handed out as copies (#2116)`() {
        let first = MockScreenFixtures.tests()
        let second = MockScreenFixtures.tests()
        #expect(!first.isEmpty)
        #expect(first.map { $0["id"] as? Int } == second.map { $0["id"] as? Int })
        // Memoized seed data, so the timestamps must be the shared ones, not rebuilt
        // (and drifting) per call.
        #expect(first.map { $0["last_activity_time"] as? Int }
            == second.map { $0["last_activity_time"] as? Int })

        // Callers get a value-type copy: mutating it must not disturb the seed.
        var mutated = first
        mutated[0]["status"] = "tampered"
        #expect(MockScreenFixtures.tests()[0]["status"] as? String != "tampered")
    }

    @Test
    func `the bad-key demo's Screen requests fail unauthorized`() async throws {
        await #expect(throws: CoderPadError.self) {
            _ = try await ScreenClient.mock(unauthorized: true).listCampaigns()
        }
    }

    @Test
    func `sending a demo invitation returns a test URL`() async throws {
        let result = try await ScreenClient.mock(key: "demo-invite")
            .sendInvitation(campaignID: 102, ScreenInvitation(candidateEmail: "newbie@example.com"))
        #expect(result.testURL?.isEmpty == false)
    }
}
