//
//  QuestionSheets+Sections.swift
//  coderpad
//
//  Split from QuestionSheets.swift to keep it within the lint length limit:
//  the draft-section model, pad-type helpers, and the draft text editor moved here.
//

import SwiftUI

let padTypeOptions = InterviewType.allCases.map(\.rawValue)
func padTypeLabel(_ raw: String) -> String {
    InterviewType(rawValue: raw)?.label ?? raw.capitalized
}

/// The interview type a new question starts as, and the fallback for anything that
/// isn't one. `padType` is plain `String` state that the create body sends straight
/// through while deriving `takeHome` from an equality check, so an unrecognized value
/// produced a payload whose two type fields disagreed (#2335).
enum QuestionPadType {
    static let fallback = InterviewType.allCases.first?.rawValue ?? "live"

    static func normalized(_ raw: String) -> String {
        InterviewType(rawValue: raw) == nil ? fallback : raw
    }
}

enum QuestionDraftSection: String, CaseIterable, Identifiable {
    case description
    case instructions
    case solution

    var id: Self {
        self
    }

    var title: LocalizedStringKey {
        switch self {
        case .description: "Brief"
        case .instructions: "Prompt"
        case .solution: "Solution"
        }
    }

    var editorTitle: LocalizedStringKey {
        switch self {
        case .description: "Brief"
        case .instructions: "Candidate Prompt"
        case .solution: "Reference Solution"
        }
    }

    var systemImage: String {
        switch self {
        case .description: "text.alignleft"
        case .instructions: "person.text.rectangle"
        case .solution: "chevron.left.forwardslash.chevron.right"
        }
    }

    var placeholder: LocalizedStringKey {
        switch self {
        case .description: "Summarize the problem an interviewer should understand before opening a pad."

        case .instructions: """
            Write the prompt candidates will see, including inputs, outputs, constraints, \
            and examples.
            """

        case .solution: "Add the reference solution or key implementation notes."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .description: "Question brief"
        case .instructions: "Candidate instructions"
        case .solution: String(localized: "Reference solution")
        }
    }
}

struct DraftTextEditor: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let accessibilityLabel: String
    var isCode = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(isCode ? .system(.body, design: .monospaced) : .body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .accessibilityLabel(accessibilityLabel)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}
