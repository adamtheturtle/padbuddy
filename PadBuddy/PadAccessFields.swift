import SwiftUI

struct PadAccessFields: View {
    @Binding var draft: PadAccessDraft
    var creation = false

    var body: some View {
        Section("Interviewer Access and Coaching") {
            OptionalBooleanPicker(title: "Restrict interviewer access", selection: $draft.restricted)
            Toggle("Replace allowed interviewer emails", isOn: $draft.replaceEmails)
            if draft.replaceEmails {
                TextField("Allowed interviewer emails", text: $draft.emails, axis: .vertical)
                    .lineLimit(2 ... 6)
                Text("An empty list removes all explicitly allowed interviewers. The owner keeps access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            OptionalBooleanPicker(title: "Disable coaching tips", selection: $draft.coachingDisabled)
        }
        if creation {
            Section("Interview Creation Options") {
                OptionalBooleanPicker(title: "Take-home interview", selection: $draft.takeHome)
                TextField("Time limit in minutes", text: $draft.timeLimit)
                OptionalBooleanPicker(title: "AI Assist", selection: $draft.aiEnabled)
                Text("Default preserves question or organization settings. Leave the time limit empty to inherit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct OptionalBooleanPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: OptionalBooleanChoice

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Default").tag(OptionalBooleanChoice.inherited)
            Text("Enabled").tag(OptionalBooleanChoice.enabled)
            Text("Disabled").tag(OptionalBooleanChoice.disabled)
        }
    }
}

struct PadAccessEditor: View {
    let client: CoderPadClient
    let pad: Pad
    let isCurrent: () -> Bool
    let onSaved: (Pad) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var draft = PadAccessDraft()
    @State private var model = PadAccessModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Interviewer Access") {
                    if let restricted = pad.restrictInterviewerAccess {
                        LabeledContent("Interviewer access") { Text(restricted ? "Restricted" : "Standard") }
                    }
                    if let emails = pad.allowedInterviewerEmails {
                        Text(verbatim: emails.joined(separator: ", "))
                    } else {
                        Text("The service did not provide the allowed interviewer list.")
                    }
                }
                PadAccessFields(draft: $draft)
                if let error = model.error ?? draft.validationMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .disabled(model.saving || isReadOnly)
            .navigationTitle("Interviewer Access and Coaching")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let saved = await model.save(draft, padID: pad.id, client: client,
                                                            isCurrent: { !isReadOnly && isCurrent() }) {
                                onSaved(saved)
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.saving || isReadOnly || !draft.hasUpdate || draft.validationMessage != nil)
                }
            }
        }
        .interactiveDismissDisabled(model.saving)
        #if os(macOS)
            .frame(minWidth: 500, minHeight: 420)
        #endif
    }
}
