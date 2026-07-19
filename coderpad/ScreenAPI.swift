//
//  ScreenAPI.swift
//  coderpad
//
//  Models for the CoderPad Screen API (formerly CodinGame for Work),
//  documented at https://api.screen.coderpad.io. This is a *separate* product
//  from the Interview API modelled in the `CoderPadKit` package: it lives on a
//  different host (`https://www.codingame.com`, or `.eu` for EU customers),
//  authenticates with an `API-Key` header rather than a bearer token, and uses
//  offset-based pagination. The networking client is `ScreenClient`.
//
//  Optional fields are tolerant of API additions; required row identity remains strict.
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
        let rawName = try container.decode(String.self, forKey: .name)
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: container, debugDescription: "Screen campaign name must not be blank."
            )
        }

        name = normalizedName
        languages = (try? container.decodeIfPresent([String].self, forKey: .languages)) ?? []
        pinned = (try? container.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        archived = (try? container.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
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

/// The result of sending an invitation: the URL the candidate uses to take it,
/// and, when returned, the new test session id.
nonisolated struct ScreenInvitationResult: Decodable, Hashable {
    let id: Int?
    let testURL: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(Int.self, forKey: .id)
        testURL = try? container.decodeIfPresent(String.self, forKey: .testURL)
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
         lastActivityTime: Int? = nil, campaignID: Int? = nil,
         url: String? = nil, testURL: String? = nil) {
        self.id = id
        self.status = status
        self.url = url
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
        self.testURL = testURL
        candidateLanguage = nil
        questions = []
        approvalStatus = nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "unknown"
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        report = try? container.decodeIfPresent(ScreenReport.self, forKey: .report)
        id = try container.decode(Int.self, forKey: .id)
        idTest = try? container.decodeIfPresent(Int.self, forKey: .idTest)
        organizationID = try? container.decodeIfPresent(String.self, forKey: .organizationID)
        campaignID = try? container.decodeIfPresent(Int.self, forKey: .campaignID)
        candidateName = try? container.decodeIfPresent(String.self, forKey: .candidateName)
        candidateEmail = try? container.decodeIfPresent(String.self, forKey: .candidateEmail)
        tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        sendTime = try ScreenEpochMilliseconds.decode(from: container, forKey: .sendTime)
        startTime = try ScreenEpochMilliseconds.decode(from: container, forKey: .startTime)
        endTime = try ScreenEpochMilliseconds.decode(from: container, forKey: .endTime)
        lastActivityTime = try ScreenEpochMilliseconds.decode(from: container, forKey: .lastActivityTime)
        testURL = try? container.decodeIfPresent(String.self, forKey: .testURL)
        candidateLanguage = try? container.decodeIfPresent(String.self, forKey: .candidateLanguage)
        questions = (try? container.decodeIfPresent([ScreenTestQuestion].self, forKey: .questions)) ?? []
        approvalStatus = try? container.decodeIfPresent(String.self, forKey: .approvalStatus)
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

/// A question within a test session and when the candidate last touched it.
nonisolated struct ScreenTestQuestion: Decodable, Identifiable, Hashable {
    let id: Int
    let lastActivityTime: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        lastActivityTime = try ScreenEpochMilliseconds.decode(from: container, forKey: .lastActivityTime)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case lastActivityTime = "last_activity_time"
    }
}

// MARK: - Reports

private nonisolated struct DynamicScreenCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private nonisolated struct LenientScreenDictionary<Value: Decodable>: Decodable {
    let values: [String: Value]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicScreenCodingKey.self)
        var decodedValues: [String: Value] = [:]

        for key in container.allKeys {
            if let value = try? container.decode(Value.self, forKey: key) {
                decodedValues[key.stringValue] = value
            }
        }

        values = decodedValues
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeLenientScreenDictionary<Value: Decodable>(
        of _: Value.Type,
        forKey key: Key
    ) -> [String: Value] {
        (try? decodeIfPresent(LenientScreenDictionary<Value>.self, forKey: key))?.values ?? [:]
    }
}

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
        duration = try? container.decodeIfPresent(Int.self, forKey: .duration)
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
        points = try? container.decodeIfPresent(Int.self, forKey: .points)
        score = try ScreenReportMetric.percentage(from: container, forKey: .score)
        technologies = container.decodeLenientScreenDictionary(of: ScreenTechnologyResult.self, forKey: .technologies)
        totalDuration = try? container.decodeIfPresent(Int.self, forKey: .totalDuration)
        totalPoints = try? container.decodeIfPresent(Int.self, forKey: .totalPoints)
        comparativeScore = try ScreenReportMetric.percentage(from: container, forKey: .comparativeScore)
        communityStats = try? container.decodeIfPresent([Int].self, forKey: .communityStats)
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
        points = try? container.decodeIfPresent(Int.self, forKey: .points)
        score = try ScreenReportMetric.percentage(from: container, forKey: .score)
        skills = container.decodeLenientScreenDictionary(of: ScreenSkillResult.self, forKey: .skills)
        totalPoints = try? container.decodeIfPresent(Int.self, forKey: .totalPoints)
        comparativeScore = try ScreenReportMetric.percentage(from: container, forKey: .comparativeScore)
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
        points = try? container.decodeIfPresent(Int.self, forKey: .points)
        score = try ScreenReportMetric.percentage(from: container, forKey: .score)
        totalPoints = try? container.decodeIfPresent(Int.self, forKey: .totalPoints)
    }

    enum CodingKeys: String, CodingKey {
        case points, score
        case totalPoints = "total_points"
    }
}
