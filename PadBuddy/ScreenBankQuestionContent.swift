import SwiftUI

struct ScreenBankQuestionContent: View {
    let question: ScreenQuestionDetails
    let locale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailSection(title: "Question Metadata", systemImage: "info.circle") {
                if let type = question.type {
                    LabeledContent("Question type", value: type)
                }
                if let difficulty = question.difficulty {
                    LabeledContent("Difficulty", value: difficulty)
                }
                if let domain = question.domain {
                    LabeledContent("Domain", value: domain)
                }
                if let skill = question.skill {
                    LabeledContent("Skill", value: skill)
                }
                if let duration = question.durationSeconds {
                    LabeledContent("Duration in seconds", value: String(duration))
                }
                if let points = question.points {
                    LabeledContent("Points", value: String(points))
                }
                if let comment = question.comment {
                    Text(verbatim: comment).textSelection(.enabled)
                }
            }
            choices
            code
            otherContent
            if let evaluation = question.evaluation {
                ScreenBankEvaluationView(evaluation: evaluation, locale: locale)
            } else {
                Text("The service did not provide evaluation details.").foregroundStyle(.secondary)
            }
            if let resources = question.resources, !resources.isEmpty {
                DetailSection(title: "Resources", systemImage: "shippingbox") {
                    ForEach(resources.indices.prefix(200), id: \.self) { index in
                        let resource = resources[index]
                        Text(verbatim: [resource.filename, resource.mimeType, resource.downloadUrl]
                            .compactMap(\.self).joined(separator: "\n"))
                            .textSelection(.enabled)
                    }
                    if resources.count > 200 {
                        Text("Some question resources are too numerous to display.")
                    }
                }
            }
        }
    }

    @ViewBuilder private var choices: some View {
        if let details = question.mcqDetails {
            DetailSection(title: "Multiple Choice", systemImage: "checklist") {
                if let mode = details.selectionMode {
                    LabeledContent("Selection mode", value: mode)
                }
                if let random = details.randomizeChoices {
                    LabeledContent("Randomize choices") { Text(random ? "Yes" : "No") }
                }
                let choices = details.choices ?? []
                ForEach(choices.indices.prefix(200), id: \.self) { index in
                    Text("Choice \(index + 1)").font(.caption.bold())
                    if let label = ScreenBankText.localized(choices[index].label, locale: locale) {
                        MarkdownText(label)
                    }
                }
                if choices.count > 200 {
                    Text("Some choices are too numerous to display.")
                }
            }
        }
    }

    @ViewBuilder private var code: some View {
        if let details = question.codeDetails {
            DetailSection(title: "Code Details", systemImage: "chevron.left.forwardslash.chevron.right") {
                if let language = details.programmingLanguageID {
                    LabeledContent("Programming language", value: language)
                }
                if let mode = details.mode {
                    LabeledContent("Evaluation mode", value: mode)
                }
                if let environment = details.environment?.environmentID {
                    LabeledContent("Environment", value: environment)
                }
                if let timeout = details.timeoutMS {
                    LabeledContent("Timeout in milliseconds", value: String(timeout))
                }
                ScreenBankCodeBlock(title: "Starter Code", text: details.starterCode)
                ScreenBankCodeBlock(title: "Candidate Test Code", text: details.candidateTestCode)
                ScreenBankCodeBlock(title: "Validator Code", text: details.validatorCode)
                ScreenBankCodeBlock(title: "Database Setup", text: details.databaseSetupScript)
                ScreenBankCodeBlock(title: "Possible Solution", text: details.possibleSolution?.code)
                if let function = details.functionSignature?.name {
                    LabeledContent("Function", value: function)
                }
            }
        }
    }

    @ViewBuilder private var otherContent: some View {
        if let details = question.projectDetails {
            DetailSection(title: "Project Details", systemImage: "folder") {
                if let environment = details.environment?.environmentID {
                    LabeledContent("Environment", value: environment)
                }
                if let allowed = details.aiAssistAllowed {
                    LabeledContent("AI Assist") { Text(allowed ? "Yes" : "No") }
                }
                if let instructions = details.aiAssistAdditionalInstructions {
                    Text(verbatim: instructions)
                }
                let resources = details.resources ?? []
                ForEach(resources.indices.prefix(200), id: \.self) { index in
                    Text(verbatim: [resources[index].resourceID, resources[index].version]
                        .compactMap(\.self).joined(separator: " · "))
                }
                if resources.count > 200 {
                    Text("Some question resources are too numerous to display.")
                }
            }
        }
        if let mode = question.textDetails?.evaluationMode {
            LabeledContent("Text evaluation mode", value: mode)
        }
        if let media = question.videoDetails?.recordingMedia {
            LabeledContent("Recording media", value: media)
        }
        if let download = question.fileUploadDetails?.downloadUrl {
            LabeledContent("File download") { Text(verbatim: download).textSelection(.enabled) }
        }
        if let languages = question.gameDetails?.availableProgrammingLanguageIDs {
            LabeledContent("Available programming languages", value: languages.joined(separator: ", "))
        }
    }
}

struct ScreenBankCodeBlock: View {
    let title: LocalizedStringKey
    let text: String?

    var body: some View {
        if let text {
            Text(title).font(.caption.bold())
            Text(verbatim: String(text.prefix(65536))).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            if text.count > 65536 {
                Text("Some code is too large to display in full.").foregroundStyle(.orange)
            }
        }
    }
}
