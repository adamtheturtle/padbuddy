//
//  coderpadTests+Screen.swift
//  coderpadTests
//
//  End-to-end tests for the Screen API layer (`ScreenClient` + `ScreenAPI`),
//  driven by an in-process `URLProtocol` that serves canned responses shaped
//  exactly like the documented CoderPad Screen API. No real network or key.
//

@testable import CoderPad
import Foundation
import Testing

// MARK: - Tests

@Suite("Screen API client")
struct ScreenClientTests {
    @Test
    func `live session bounds request and total resource duration`() {
        let configuration = ScreenClient.makeLiveConfiguration()

        #expect(configuration.timeoutIntervalForRequest == 60)
        #expect(configuration.timeoutIntervalForResource == 120)
    }

    @Test
    func `listCampaigns decodes campaigns and their languages`() async throws {
        // The fixture includes one malformed entry; it must be dropped, not hide
        // the valid campaigns behind a decode error (#896).
        let campaigns = try await screenClient().listCampaigns()
        #expect(campaigns.count == 2)
        let backend = try #require(campaigns.first { $0.id == 42 })
        #expect(backend.name == "Backend Screen")
        #expect(backend.languages == ["java", "python"])
        #expect(backend.pinned)
        // The key-path form (`contains(where: \.archived)`) trips a spurious
        // "call can throw" diagnostic inside the #expect macro expansion.
        // swiftlint:disable:next prefer_key_path
        #expect(campaigns.contains { $0.archived })
    }

    @Test
    func `sendInvitation posts to a campaign and returns the test session`() async throws {
        let result = try await screenClient().sendInvitation(
            campaignID: 42,
            ScreenInvitation(candidateEmail: "candidate@example.com",
                             candidateName: "Pat",
                             sendInvitationEmail: true)
        )
        #expect(result.id == 999)
        #expect(result.testURL == "https://screen-ide.coderpad.io/?id=999abc")
    }

    @Test(arguments: [0, -1, Int.min])
    func `campaign endpoint rejects nonpositive IDs before transport`(id: Int) async {
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: .ephemeral))
        do {
            _ = try await client.sendInvitation(campaignID: id, ScreenInvitation(candidateEmail: "a@example.com"))
            Issue.record("Expected an invalid campaign ID to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("campaign ID must be positive"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [0, -1, Int.min])
    func `endpoints reject nonpositive IDs before transport`(id: Int) async {
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: .ephemeral))
        do {
            _ = try await client.getTest(id: id)
            Issue.record("Expected an invalid test ID to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("test ID must be positive"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `sendInvitation accepts a successful response without an id`() async throws {
        let result = try await screenClient().sendInvitation(
            campaignID: 43,
            ScreenInvitation(candidateEmail: "candidate@example.com")
        )
        #expect(result.id == nil)
        #expect(result.testURL == "https://screen-ide.coderpad.io/?id=no-session-id")
    }

    @Test
    func `listTests returns the first page with offset pagination`() async throws {
        let page = try await screenClient().listTests(campaignID: 42)
        #expect(page.tests.count == 2)
        #expect(page.tests.first?.candidateName == "Ada")
        let pagination = try #require(page.pagination)
        #expect(pagination.hasMoreItems)
        #expect(pagination.nextStart == 2)
        #expect(pagination.total == 3)
    }

    @Test(arguments: [-1, 0, ScreenClient.maximumPageSize + 1, Int.max])
    func `listTests rejects invalid page limits before transport`(limit: Int) async {
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: .ephemeral))
        do {
            _ = try await client.listTests(limit: limit)
            Issue.record("Expected an invalid pagination limit to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("limit must be between"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `listTests accepts the maximum page limit`() async throws {
        _ = try await screenClient().listTests(limit: ScreenClient.maximumPageSize)
    }

    @Test
    func `listTests rejects a negative starting offset before transport`() async {
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: .ephemeral))
        do {
            _ = try await client.listTests(start: -1)
            Issue.record("Expected a negative pagination start to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("start must not be negative"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `listTests keeps valid sessions when one page item is malformed (#764)`() async throws {
        let page = try await screenClient().listTests(candidateEmail: "malformed@example.com")

        #expect(page.tests.map(\.id) == [1, 2])
        #expect(page.pagination?.total == 3)
    }

    @Test
    func `listAllTests follows pagination to the end`() async throws {
        let all = try await screenClient().listAllTests(campaignID: 42)
        #expect(all.count == 3)
        #expect(all.map(\.id) == [1, 2, 3])
        #expect(all.last?.status == "aborted")
    }

    @Test
    func `getTest decodes a completed report with nested technologies and skills`() async throws {
        let test = try await screenClient().getTest(id: 13_188_658)
        #expect(test.status == "completed")
        #expect(test.candidateName == "Luke Duncan")
        #expect(test.approvalStatus == "TO_REVIEW")
        let report = try #require(test.report)
        #expect(report.points == 530)
        #expect(report.warnings.count == 2)
        #expect(report.totalPoints == 630)
        let java = try #require(report.technologies["Java"])
        #expect(java.points == 80)
        let problemSolving = try #require(java.skills["Problem solving"])
        #expect(problemSolving.totalPoints == 100)
        #expect(problemSolving.score == 80.0)
    }

    @Test
    func `report keeps valid score entries when sibling entries are malformed (#861)`() throws {
        let json = """
        {
          "technologies": {
            "Java": {
              "skills": {
                "Problem solving": {
                  "score": 80,
                  "total_points": 100
                },
                "Malformed skill": "unscored"
              }
            },
            "Malformed technology": "unscored"
          }
        }
        """

        let report = try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))
        let java = try #require(report.technologies["Java"])
        let problemSolving = try #require(java.skills["Problem solving"])

        #expect(problemSolving.score == 80)
        #expect(problemSolving.totalPoints == 100)
        #expect(report.technologies["Malformed technology"] == nil)
        #expect(java.skills["Malformed skill"] == nil)
    }

    @Test
    func `epoch-millisecond timestamps convert to Dates`() async throws {
        let test = try await screenClient().getTest(id: 13_188_658)
        let sendDate = try #require(test.sendDate)
        // 1769042802384 ms == 2026-01-22 in UTC; just assert the round-trip math.
        #expect(Int(sendDate.timeIntervalSince1970 * 1000) == 1_769_042_802_384)
        #expect(test.startDate != nil)
        #expect(test.endDate != nil)
        #expect(test.questions.first?.lastActivityTime == 1_769_043_248_900)
    }

    @Test
    func `cancel, resend, and delete succeed on a 204 response`() async throws {
        let client = screenClient()
        try await client.cancelTest(id: 13_188_658)
        try await client.resendTest(id: 13_188_658)
        try await client.deleteTest(id: 13_188_658)
    }

    @Test
    func `webhookURL reads the configured callback`() async throws {
        let url = try await screenClient().webhookURL()
        #expect(url == "https://example.com/hook")
    }

    @Test
    func `an empty API key fails fast without a request`() async throws {
        let client = ScreenClient(apiKey: "", session: URLSession(configuration: .ephemeral))
        await #expect(throws: CoderPadError.self) {
            _ = try await client.listCampaigns()
        }
    }

    @Test
    func `a next offset cycle terminates with an error instead of looping (#857)`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().listAllTests(campaignID: 666)
        }
    }

    @Test
    func `more items with no usable next offset raises instead of silent partial data (#858)`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().listAllTests(campaignID: 555)
        }
    }

    @Test
    func `sessions re-served across pages are deduplicated (#898)`() async throws {
        let all = try await screenClient().listAllTests(campaignID: 777)
        #expect(all.map(\.id) == [30, 31, 32])
    }

    @Test
    func `a report that is a PDF is returned`() async throws {
        let data = try await screenClient().testReport(id: 13_188_658)
        #expect(data.starts(with: Array("%PDF".utf8)))
    }

    @Test
    func `a non-PDF report response raises instead of being saved as a PDF (#859)`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().testReport(id: 424_242)
        }
    }

    @Test
    func `an unknown test id surfaces a mapped 404`() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().getTest(id: 1)
        }
        if case let .http(code, _) = error {
            #expect(code == 404)
        } else {
            Issue.record("Expected a .http error, got \(String(describing: error))")
        }
    }
}

@Suite("Screen API unauthorized")
struct ScreenClientUnauthorizedTests {
    @Test
    func `an invalid API key surfaces an unauthorized CoderPadError`() async throws {
        let client = screenClient(ScreenAPIUnauthorizedMockURLProtocol.self)
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await client.listCampaigns()
        }
        #expect(error?.isUnauthorized == true)
        if case let .http(code, _) = error {
            #expect(code == 401)
        } else {
            Issue.record("Expected a .http error, got \(String(describing: error))")
        }
    }
}

@Suite("Screen session link fallback")
struct ScreenSessionURLTests {
    @Test
    func `valid recruiter URL wins over the candidate URL`() {
        let session = ScreenTestSession(id: 1, url: "https://a.example/review",
                                        testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://a.example/review")
    }

    @Test
    func `malformed recruiter URL falls back to the candidate URL`() {
        let session = ScreenTestSession(id: 1, url: "not a url",
                                        testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://b.example/take")
    }

    @Test
    func `empty recruiter URL falls back to the candidate URL`() {
        let session = ScreenTestSession(id: 1, url: "", testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://b.example/take")
    }

    @Test
    func `non-web schemes are rejected`() {
        let session = ScreenTestSession(id: 1, url: "file:///etc/hosts",
                                        testURL: "javascript:alert(1)")
        #expect(session.screenURL == nil)
    }

    @Test
    func `no links at all yields nil`() {
        #expect(ScreenTestSession(id: 1).screenURL == nil)
    }
}

@Suite("Screen invitation email validation")
struct ScreenInviteEmailTests {
    @Test
    func `plausible addresses are accepted`() {
        #expect(ScreenInviteSheet.isPlausibleEmail("ada@example.com"))
        #expect(ScreenInviteSheet.isPlausibleEmail("a.b+tag@sub.example.co"))
    }

    @Test
    func `malformed addresses are rejected (#874, #920)`() {
        let bad = ["", "\n", "not-an-email", "@example.com", "a@b", "a@.com",
                   "a@example.com.", "two words@example.com", "a@@example.com"]
        for value in bad {
            #expect(!ScreenInviteSheet.isPlausibleEmail(value), "\(value) should be rejected")
        }
    }
}
