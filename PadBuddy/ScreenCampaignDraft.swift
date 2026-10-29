import Foundation

struct ScreenRandomQuestionDraft: Equatable {
    var domain = ""
    var skills = ""
    var questionType: ScreenRandomQuestionConfiguration.QuestionType?
    var duration = ""
    var experience: ScreenRandomQuestionConfiguration.ExperienceLevel?
    var include = true
    var ids = ""

    var parsedIDs: [UUID] {
        split(ids).compactMap(UUID.init(uuidString:))
    }

    var validationMessage: String? {
        if let durationMessage = ScreenCampaignDraft.positiveIntegerMessage(duration) {
            return durationMessage
        }
        let values = split(ids)
        if values.count > 200 || parsedIDs.count != values.count || Set(parsedIDs).count != parsedIDs.count {
            return String(localized: "Use up to 200 unique question UUIDs separated by commas or new lines.")
        }
        return nil
    }

    var request: ScreenRandomQuestionConfiguration {
        let minutes = ScreenCampaignDraft.optional(duration).flatMap(Int.init)
        let parsedSkills = split(skills)
        return ScreenRandomQuestionConfiguration(
            domain: ScreenCampaignDraft.optional(domain),
            skills: parsedSkills.isEmpty ? nil : parsedSkills, questionType: questionType,
            targetDurationMinutes: minutes,
            targetExperienceLevel: experience,
            includedQuestionIDs: include && !parsedIDs.isEmpty ? parsedIDs : nil,
            excludedQuestionIDs: !include && !parsedIDs.isEmpty ? parsedIDs : nil
        )
    }

    private func split(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct ScreenCampaignQuestionDraft: Identifiable, Equatable {
    let id = UUID()
    var questionID: UUID?
    var random: ScreenRandomQuestionDraft?

    var request: ScreenCampaignQuestion? {
        if let random {
            return .randomQuestionSet(random.request)
        }
        return questionID.map(ScreenCampaignQuestion.question)
    }
}

struct ScreenCampaignDraft: Equatable {
    var name = ""
    var teamID = ""
    var questions: [ScreenCampaignQuestionDraft] = []
    var settings = ScreenCampaignSettingsDraft()

    var validationMessage: String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3 ... 64).contains(name.count) else {
            return String(localized: "Campaign name must contain 3 to 64 characters.")
        }
        guard !questions.isEmpty, questions.count <= 200 else {
            return String(localized: "Choose between 1 and 200 questions or random question sets.")
        }
        guard Self.optional(teamID) == nil || Self.optional(teamID).flatMap(UUID.init(uuidString:)) != nil else {
            return String(localized: "Enter a valid team UUID or leave it empty for the default team.")
        }
        guard questions.allSatisfy({ $0.request != nil }) else {
            return String(localized: "Select a question for every fixed question row.")
        }

        let fixed = questions.compactMap(\.questionID)
        guard Set(fixed).count == fixed.count else {
            return String(localized: "Each fixed question can only be selected once.")
        }

        for question in questions {
            if let message = question.random?.validationMessage {
                return message
            }
        }
        return settings.validationMessage
    }

    var request: ScreenCampaignCreation {
        ScreenCampaignCreation(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               questions: questions.compactMap(\.request), settings: settings.request,
                               teamID: Self.optional(teamID).flatMap(UUID.init(uuidString:)))
    }

    static func optional(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func positiveIntegerMessage(_ value: String) -> String? {
        guard let value = optional(value) else { return nil }
        guard let integer = Int(value), (1 ... Int(Int32.max)).contains(integer) else {
            return String(localized: "Enter a whole number from 1 to 2147483647 or leave it empty for the default.")
        }

        return nil
    }
}

@Observable
final class ScreenCampaignCreationModel {
    private(set) var saving = false
    private(set) var error: String?
    private(set) var createdID: Int?
    private(set) var contextChangedAfterCreation = false

    func create(_ draft: ScreenCampaignDraft, client: ScreenClient, isCurrent: () -> Bool) async -> Int? {
        guard !saving, createdID == nil, draft.validationMessage == nil else { return nil }

        saving = true
        error = nil
        defer { saving = false }
        do {
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }
            guard try JSONEncoder().encode(draft.request).count <= 1024 * 1024 else {
                throw CoderPadError.decode(String(localized: "Campaign settings are too large to submit."))
            }

            let created = try await client.createCampaign(draft.request)
            // Record a successful creation before checking selection again. Retrying
            // after a credential change would create a second campaign.
            createdID = created.id
            contextChangedAfterCreation = !isCurrent() || Task.isCancelled
            return contextChangedAfterCreation ? nil : created.id
        } catch is CancellationError {
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
