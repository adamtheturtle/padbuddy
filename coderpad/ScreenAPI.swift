//
//  ScreenAPI.swift
//  coderpad
//
//  Models for the CoderPad Screen API (formerly CodinGame for Work),
//  documented at https://api.screen.coderpad.io. This is a *separate* product
//  from the Interview API modelled in `CoderPadAPI.swift`: it lives on a
//  different host (`https://www.codingame.com`, or `.eu` for EU customers),
//  authenticates with an `API-Key` header rather than a bearer token, and uses
//  offset-based pagination. The networking client is `ScreenClient`.
//
//  These decode-only models reuse `loggedDecodeIfPresent` (defined in
//  CoderPadAPI.swift) so a field the API adds or omits never fails the whole
//  decode — the docs explicitly warn that new response fields may appear within
//  this API version without a version bump.
//

import Foundation

// MARK: - Campaigns

/// A test campaign (a reusable assessment template) you can send to candidates.
/// Returned by `GET /campaigns`.
nonisolated struct ScreenCampaign: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    /// Programming languages the candidate may answer in.
    let languages: [String]
    let pinned: Bool
    let archived: Bool

    /// Memberwise init for tests and previews; the live decode path uses `init(from:)`.
    init(id: Int, name: String, languages: [String] = [], pinned: Bool = false, archived: Bool = false) {
        self.id = id
        self.name = name
        self.languages = languages
        self.pinned = pinned
        self.archived = archived
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.loggedDecodeIfPresent(String.self, forKey: .name) ?? ""
        languages = container.loggedDecodeIfPresent([String].self, forKey: .languages) ?? []
        pinned = container.loggedDecodeIfPresent(Bool.self, forKey: .pinned) ?? false
        archived = container.loggedDecodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case id, name, languages, pinned, archived
    }
}

// MARK: - Sending invitations

/// The request body for `POST /campaigns/:id/actions/send`. All fields are
/// optional; omitting `candidateEmail` creates a test the recruiter can hand to
/// a candidate manually rather than emailing an invitation.
nonisolated struct ScreenInvitation: Encodable, Hashable {
    var candidateEmail: String?
    var candidateName: String?
    /// Recruiter who receives the result notification.
    var recruiterEmail: String?
    /// Free-form tags, sent as a single string per the API contract.
    var tags: String?
    var sendInvitationEmail: Bool?
    var sendNotificationEmailOnBounce: Bool?

    init(candidateEmail: String? = nil,
         candidateName: String? = nil,
         recruiterEmail: String? = nil,
         tags: String? = nil,
         sendInvitationEmail: Bool? = nil,
         sendNotificationEmailOnBounce: Bool? = nil) {
        self.candidateEmail = candidateEmail
        self.candidateName = candidateName
        self.recruiterEmail = recruiterEmail
        self.tags = tags
        self.sendInvitationEmail = sendInvitationEmail
        self.sendNotificationEmailOnBounce = sendNotificationEmailOnBounce
    }

    enum CodingKeys: String, CodingKey {
        case candidateEmail = "candidate_email"
        case candidateName = "candidate_name"
        case recruiterEmail = "recruiter_email"
        case tags
        case sendInvitationEmail = "send_invitation_email"
        case sendNotificationEmailOnBounce = "send_notification_email_on_bounce"
    }
}

/// The result of sending an invitation: the new test session id and the URL the
/// candidate uses to take it.
nonisolated struct ScreenInvitationResult: Decodable, Hashable {
    let id: Int
    let testURL: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        testURL = container.loggedDecodeIfPresent(String.self, forKey: .testURL)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case testURL = "test_url"
    }
}

// MARK: - Test sessions

/// One candidate's run of a campaign. Returned (in a list) by `GET /tests` and
/// (singly) by `GET /tests/:id`. The `report` is populated once the candidate
/// finishes; before then most timing fields and the report are absent.
nonisolated struct ScreenTestSession: Decodable, Identifiable, Hashable {
    /// e.g. "waiting", "in_progress", "completed", "aborted", "cancelled".
    let status: String
    /// Dashboard URL for a recruiter to review this candidate.
    let url: String?
    let report: ScreenReport?
    let id: Int
    /// The underlying test id. Usually equal to `id`, but exposed verbatim.
    let idTest: Int?
    let organizationID: String?
    let campaignID: Int?
    let candidateName: String?
    let candidateEmail: String?
    let tags: [String]
    /// Epoch-millisecond timestamps; use the `*Date` accessors for `Date` values.
    let sendTime: Int?
    let startTime: Int?
    let endTime: Int?
    let lastActivityTime: Int?
    /// URL the candidate uses to take the test.
    let testURL: String?
    /// The candidate's chosen UI language, e.g. "en".
    let candidateLanguage: String?
    let questions: [ScreenTestQuestion]
    /// e.g. "TO_REVIEW", once a human review workflow applies.
    let approvalStatus: String?

    /// Memberwise init for tests and previews; the live decode path uses `init(from:)`.
    init(id: Int, status: String = "waiting", report: ScreenReport? = nil,
         candidateName: String? = nil, candidateEmail: String? = nil, tags: [String] = [],
         sendTime: Int? = nil, startTime: Int? = nil, endTime: Int? = nil,
         lastActivityTime: Int? = nil, campaignID: Int? = nil) {
        self.id = id
        self.status = status
        url = nil
        self.report = report
        idTest = nil
        organizationID = nil
        self.campaignID = campaignID
        self.candidateName = candidateName
        self.candidateEmail = candidateEmail
        self.tags = tags
        self.sendTime = sendTime
        self.startTime = startTime
        self.endTime = endTime
        self.lastActivityTime = lastActivityTime
        testURL = nil
        candidateLanguage = nil
        questions = []
        approvalStatus = nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.loggedDecodeIfPresent(String.self, forKey: .status) ?? "unknown"
        url = container.loggedDecodeIfPresent(String.self, forKey: .url)
        report = container.loggedDecodeIfPresent(ScreenReport.self, forKey: .report)
        id = try container.decode(Int.self, forKey: .id)
        idTest = container.loggedDecodeIfPresent(Int.self, forKey: .idTest)
        organizationID = container.loggedDecodeIfPresent(String.self, forKey: .organizationID)
        campaignID = container.loggedDecodeIfPresent(Int.self, forKey: .campaignID)
        candidateName = container.loggedDecodeIfPresent(String.self, forKey: .candidateName)
        candidateEmail = container.loggedDecodeIfPresent(String.self, forKey: .candidateEmail)
        tags = container.loggedDecodeIfPresent([String].self, forKey: .tags) ?? []
        sendTime = container.loggedDecodeIfPresent(Int.self, forKey: .sendTime)
        startTime = container.loggedDecodeIfPresent(Int.self, forKey: .startTime)
        endTime = container.loggedDecodeIfPresent(Int.self, forKey: .endTime)
        lastActivityTime = container.loggedDecodeIfPresent(Int.self, forKey: .lastActivityTime)
        testURL = container.loggedDecodeIfPresent(String.self, forKey: .testURL)
        candidateLanguage = container.loggedDecodeIfPresent(String.self, forKey: .candidateLanguage)
        questions = container.loggedDecodeIfPresent([ScreenTestQuestion].self, forKey: .questions) ?? []
        approvalStatus = container.loggedDecodeIfPresent(String.self, forKey: .approvalStatus)
    }

    enum CodingKeys: String, CodingKey {
        case status, url, report, id, tags, questions
        case idTest = "id_test"
        case organizationID = "organization_id"
        case campaignID = "campaign_id"
        case candidateName = "candidate_name"
        case candidateEmail = "candidate_email"
        case sendTime = "send_time"
        case startTime = "start_time"
        case endTime = "end_time"
        case lastActivityTime = "last_activity_time"
        case testURL = "test_url"
        case candidateLanguage = "candidate_language"
        case approvalStatus = "approval_status"
    }
}

extension ScreenTestSession {
    /// When the invitation was sent.
    var sendDate: Date? {
        Self.date(fromMilliseconds: sendTime)
    }

    /// When the candidate started the test.
    var startDate: Date? {
        Self.date(fromMilliseconds: startTime)
    }

    /// When the candidate finished (or the test was aborted).
    var endDate: Date? {
        Self.date(fromMilliseconds: endTime)
    }

    /// The candidate's most recent activity.
    var lastActivityDate: Date? {
        Self.date(fromMilliseconds: lastActivityTime)
    }

    private static func date(fromMilliseconds millis: Int?) -> Date? {
        guard let millis else { return nil }

        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }
}

/// A question within a test session and when the candidate last touched it.
nonisolated struct ScreenTestQuestion: Decodable, Identifiable, Hashable {
    let id: Int
    let lastActivityTime: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        lastActivityTime = container.loggedDecodeIfPresent(Int.self, forKey: .lastActivityTime)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case lastActivityTime = "last_activity_time"
    }
}

// MARK: - Reports

/// A candidate's scored results, present once the test is completed.
nonisolated struct ScreenReport: Decodable, Hashable {
    /// Time spent, in seconds.
    let duration: Int?
    /// Proctoring/anti-cheat warnings raised during the test.
    let warnings: [String]
    let points: Int?
    /// Overall score as a percentage (0–100).
    let score: Double?
    /// Per-technology breakdown, keyed by technology name (e.g. "Java").
    let technologies: [String: ScreenTechnologyResult]
    let totalDuration: Int?
    let totalPoints: Int?
    let comparativeScore: Double?
    /// Score distribution buckets across the candidate community, when requested
    /// with `withCommunityStats`.
    let communityStats: [Int]?

    /// Memberwise init for tests and previews; the live decode path uses `init(from:)`.
    init(score: Double? = nil, points: Int? = nil, duration: Int? = nil,
         warnings: [String] = [], technologies: [String: ScreenTechnologyResult] = [:],
         totalDuration: Int? = nil, totalPoints: Int? = nil,
         comparativeScore: Double? = nil, communityStats: [Int]? = nil) {
        self.duration = duration
        self.warnings = warnings
        self.points = points
        self.score = score
        self.technologies = technologies
        self.totalDuration = totalDuration
        self.totalPoints = totalPoints
        self.comparativeScore = comparativeScore
        self.communityStats = communityStats
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = container.loggedDecodeIfPresent(Int.self, forKey: .duration)
        warnings = container.loggedDecodeIfPresent([String].self, forKey: .warnings) ?? []
        points = container.loggedDecodeIfPresent(Int.self, forKey: .points)
        score = container.loggedDecodeIfPresent(Double.self, forKey: .score)
        technologies = container.loggedDecodeIfPresent([String: ScreenTechnologyResult].self,
                                                       forKey: .technologies) ?? [:]
        totalDuration = container.loggedDecodeIfPresent(Int.self, forKey: .totalDuration)
        totalPoints = container.loggedDecodeIfPresent(Int.self, forKey: .totalPoints)
        comparativeScore = container.loggedDecodeIfPresent(Double.self, forKey: .comparativeScore)
        communityStats = container.loggedDecodeIfPresent([Int].self, forKey: .communityStats)
    }

    enum CodingKeys: String, CodingKey {
        case duration, warnings, points, score, technologies
        case totalDuration = "total_duration"
        case totalPoints = "total_points"
        case comparativeScore = "comparative_score"
        case communityStats = "community_stats"
    }
}

/// Per-technology results within a report, with a further per-skill breakdown.
nonisolated struct ScreenTechnologyResult: Decodable, Hashable {
    let points: Int?
    let score: Double?
    /// Per-skill breakdown, keyed by skill name (e.g. "Problem solving").
    let skills: [String: ScreenSkillResult]
    let totalPoints: Int?
    let comparativeScore: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = container.loggedDecodeIfPresent(Int.self, forKey: .points)
        score = container.loggedDecodeIfPresent(Double.self, forKey: .score)
        skills = container.loggedDecodeIfPresent([String: ScreenSkillResult].self, forKey: .skills) ?? [:]
        totalPoints = container.loggedDecodeIfPresent(Int.self, forKey: .totalPoints)
        comparativeScore = container.loggedDecodeIfPresent(Double.self, forKey: .comparativeScore)
    }

    enum CodingKeys: String, CodingKey {
        case points, score, skills
        case totalPoints = "total_points"
        case comparativeScore = "comparative_score"
    }
}

/// A single skill's score within a technology result.
nonisolated struct ScreenSkillResult: Decodable, Hashable {
    let points: Int?
    let score: Double?
    let totalPoints: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = container.loggedDecodeIfPresent(Int.self, forKey: .points)
        score = container.loggedDecodeIfPresent(Double.self, forKey: .score)
        totalPoints = container.loggedDecodeIfPresent(Int.self, forKey: .totalPoints)
    }

    enum CodingKeys: String, CodingKey {
        case points, score
        case totalPoints = "total_points"
    }
}

// MARK: - Pagination

/// One page of test sessions from `GET /tests`. Unlike the Interview API's
/// cursor-URL pagination, Screen uses offset/limit: pass `nextStart` as the next
/// request's `start` while `hasMoreItems` is true.
nonisolated struct ScreenTestsPage: Decodable, Hashable {
    let tests: [ScreenTestSession]
    let pagination: ScreenPagination?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tests = container.loggedDecodeIfPresent([ScreenTestSession].self, forKey: .tests) ?? []
        pagination = container.loggedDecodeIfPresent(ScreenPagination.self, forKey: .pagination)
    }

    enum CodingKeys: String, CodingKey {
        case tests, pagination
    }
}

nonisolated struct ScreenPagination: Decodable, Hashable {
    let start: Int?
    let limit: Int?
    let total: Int?
    let hasMoreItems: Bool
    let nextStart: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = container.loggedDecodeIfPresent(Int.self, forKey: .start)
        limit = container.loggedDecodeIfPresent(Int.self, forKey: .limit)
        total = container.loggedDecodeIfPresent(Int.self, forKey: .total)
        hasMoreItems = container.loggedDecodeIfPresent(Bool.self, forKey: .hasMoreItems) ?? false
        nextStart = container.loggedDecodeIfPresent(Int.self, forKey: .nextStart)
    }

    enum CodingKeys: String, CodingKey {
        case start, limit, total
        case hasMoreItems = "has_more_items"
        case nextStart = "next_start"
    }
}
