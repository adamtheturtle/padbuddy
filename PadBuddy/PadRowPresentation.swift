import Foundation

struct PadRowPresentation: Equatable {
    let title: String
    let owner: String
    let state: PadState
    let language: String?
    let interviewType: InterviewType?
    let accessibilityLabel: String

    init(pad: Pad, account: RowAccount?, owner: String) {
        title = pad.displayListTitle
        self.owner = ExternalText.singleLine(owner, limit: 120)
        state = pad.status
        language = pad.language.flatMap {
            let bounded = ExternalText.singleLine($0, limit: 64)
            return bounded.isEmpty ? nil : bounded.coderPadLanguageDisplayName
        }
        interviewType = pad.interviewType
        var parts = [title, state.label]
        if let account {
            parts.append(ExternalText.singleLine(account.name, limit: 80))
        }
        if let language {
            parts.append(language)
        }
        if interviewType == .takeHome {
            parts.append(InterviewType.takeHome.label)
        }
        parts.append(self.owner)
        if let updated = pad.informativeUpdatedAt {
            parts.append(String(localized: "Updated \(RelativeDateLabel.labels(for: updated).relative)"))
        }
        accessibilityLabel = parts.joined(separator: ", ")
    }
}
