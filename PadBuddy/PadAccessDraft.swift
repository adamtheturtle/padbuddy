import Foundation

enum OptionalBooleanChoice: String, Codable, CaseIterable {
    case inherited
    case enabled
    case disabled

    var value: Bool? {
        switch self {
        case .inherited: nil
        case .enabled: true
        case .disabled: false
        }
    }
}

struct PadAccessDraft: Codable, Equatable {
    var restricted = OptionalBooleanChoice.inherited
    var replaceEmails = false
    var emails = ""
    var coachingDisabled = OptionalBooleanChoice.inherited
    var takeHome = OptionalBooleanChoice.inherited
    var timeLimit = ""
    var aiEnabled = OptionalBooleanChoice.inherited

    var replacementEmails: [String]? {
        guard replaceEmails else { return nil }

        return emails.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map(EmailValidation.normalized).filter { !$0.isEmpty }
    }

    var validationMessage: String? {
        if let addresses = replacementEmails {
            if addresses.count > 100 {
                return String(localized: "Use 100 or fewer interviewer email addresses.")
            }
            if !addresses.allSatisfy(EmailValidation.isPlausibleAddress) {
                return String(localized: "Enter valid interviewer email addresses separated by commas or new lines.")
            }
        }
        let trimmed = timeLimit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let minutes = Int(trimmed), (0 ... Int(Int32.max)).contains(minutes) else {
                return String(localized: "Enter a whole number of minutes from 0 to 2147483647, or leave it empty.")
            }

            if takeHome == .disabled {
                return String(localized: "A time limit requires a take-home pad or the inherited pad type.")
            }
        }
        return nil
    }

    var isMeaningful: Bool {
        self != Self()
    }

    var hasUpdate: Bool {
        restricted != .inherited || replaceEmails || coachingDisabled != .inherited
    }

    func update(padID: String) -> PadUpdate {
        PadUpdate(id: padID, restrictInterviewerAccess: restricted.value,
                  allowedInterviewerEmails: replacementEmails, disableCoachingTips: coachingDisabled.value)
    }

    func applying(to body: PadCreate) -> PadCreate {
        var body = body
        body.restrictInterviewerAccess = restricted.value
        body.allowedInterviewerEmails = replacementEmails
        body.disableCoachingTips = coachingDisabled.value
        body.takeHome = takeHome.value
        body.takeHomeTimeLimit = Int(timeLimit.trimmingCharacters(in: .whitespacesAndNewlines))
        body.aiAssistEnabled = aiEnabled.value
        return body
    }
}

@Observable
final class PadAccessModel {
    private(set) var saving = false
    private(set) var error: String?

    func save(_ draft: PadAccessDraft, padID: String, client: CoderPadClient,
              isCurrent: () -> Bool) async -> Pad? {
        guard !saving, draft.hasUpdate, draft.validationMessage == nil else { return nil }

        saving = true
        error = nil
        defer { saving = false }
        do {
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }

            let pad = try await client.updatePad(draft.update(padID: padID))
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }

            return pad
        } catch is CancellationError {
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
