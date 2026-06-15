//
//  PadDetailView+Edit.swift
//  coderpad
//
//  Inline, save-per-field editing for a pad's properties. Replaces the former
//  modal edit sheet: each control commits its own `PUT /api/pads/:id` carrying
//  only the field that changed, so nothing else on the pad is touched.
//

import SwiftUI

extension PadDetailView {
    /// The editable pad properties, presented as labeled rows of inline controls.
    /// Title is edited in the header; language, owner, and the two flags live here.
    var propertiesCard: some View {
        DetailSection(title: "Properties", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                propertyRow("Language") {
                    Picker("", selection: languageBinding) {
                        ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                            Text($0.languageDisplayName).tag($0)
                        }
                        // Keep the pad's current language selectable even when it
                        // isn't one of the common picker options.
                        if !CoderPadLanguages.pickerOptions.contains(draftLanguage) {
                            Text(draftLanguage.languageDisplayName).tag(draftLanguage)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                propertyRow("Owner") {
                    SearchableOwnerPicker(ownerEmail: ownerBinding,
                                          users: orgUsers,
                                          keyOwnerEmail: AccountsStore.shared.currentAccount?.userEmail)
                }
                propertyRow("Private") {
                    Toggle("", isOn: privateBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                propertyRow("Execution enabled") {
                    Toggle("", isOn: executionBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        // Offline → read-only: disable the inline property editors so a field change
        // can't fire a doomed PUT against an unreachable server (#321).
        .disabled(isReadOnly)
        .task(id: pad.id) { await loadOrgUsers() }
    }

    /// A labeled row pairing a property name with its inline control, matching the
    /// alignment of the read-only `LabeledRow`s in the Details section.
    @ViewBuilder
    private func propertyRow<Control: View>(_ label: String,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bindings

    // Each binding reads its optimistic draft and, on a user change, updates the
    // draft immediately before kicking off the field's save. Reseeding a draft from
    // the pad (see `seedDrafts`) never goes through these setters, so there's no
    // commit loop when a save returns a refreshed pad.

    private var languageBinding: Binding<String> {
        Binding(get: { draftLanguage },
                set: { newValue in draftLanguage = newValue; Task { await commitLanguage(newValue) } })
    }

    private var ownerBinding: Binding<String> {
        Binding(get: { draftOwner },
                set: { newValue in draftOwner = newValue; Task { await commitOwner(newValue) } })
    }

    private var privateBinding: Binding<Bool> {
        Binding(get: { draftIsPrivate },
                set: { newValue in draftIsPrivate = newValue; Task { await commitPrivate(newValue) } })
    }

    private var executionBinding: Binding<Bool> {
        Binding(get: { draftExecution },
                set: { newValue in draftExecution = newValue; Task { await commitExecution(newValue) } })
    }

    // MARK: - Drafts

    /// Seeds every editable draft from the pad. Called on appear and whenever a
    /// different pad is shown.
    func seedDrafts() {
        titleDraft = pad.title
        draftLanguage = pad.language ?? "python3"
        draftOwner = pad.ownerEmail
        draftIsPrivate = pad.isPrivate ?? false
        draftExecution = pad.executionEnabled ?? true
    }

    /// Loads org members so the owner picker offers a searchable, named list. Falls
    /// back silently to free-text email entry when unavailable.
    private func loadOrgUsers() async {
        guard orgUsers.isEmpty, !client.apiKey.isEmpty else { return }
        if let org = try? await client.organization() {
            orgUsers = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        }
    }

    // MARK: - Per-field commits

    func commitTitle() async {
        let newTitle = titleDraft
        guard newTitle != pad.title else { return }
        await save(PadUpdate(id: pad.id, title: newTitle)) { titleDraft = pad.title }
    }

    func commitLanguage(_ language: String) async {
        guard language != pad.language else { return }
        await save(PadUpdate(id: pad.id, language: language)) { draftLanguage = pad.language ?? "python3" }
    }

    func commitOwner(_ email: String) async {
        let normalized = email.trimmingCharacters(in: .whitespaces)
        guard normalized != pad.ownerEmail else { return }
        // An empty owner makes the server resolve the pad to the key owner.
        await save(PadUpdate(id: pad.id, ownerEmail: normalized.isEmpty ? nil : normalized)) {
            draftOwner = pad.ownerEmail
        }
    }

    func commitPrivate(_ isPrivate: Bool) async {
        guard isPrivate != (pad.isPrivate ?? false) else { return }
        await save(PadUpdate(id: pad.id, isPrivate: isPrivate)) { draftIsPrivate = pad.isPrivate ?? false }
    }

    func commitExecution(_ enabled: Bool) async {
        guard enabled != (pad.executionEnabled ?? true) else { return }
        await save(PadUpdate(id: pad.id, executionEnabled: enabled)) { draftExecution = pad.executionEnabled ?? true }
    }

    /// Sends a single-field update and propagates the refreshed pad. On failure it
    /// surfaces the error and runs `revert` to snap the field back to the server's
    /// value, so the control never lies about what's saved.
    private func save(_ body: PadUpdate, revert: () -> Void) async {
        do {
            let updated = try await client.updatePad(body)
            AppRouter.padUpdated(updated)
        } catch {
            mutateError = error.localizedDescription
            revert()
        }
    }
}
