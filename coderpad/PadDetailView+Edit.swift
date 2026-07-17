//
//  PadDetailView+Edit.swift
//  coderpad
//
//  Inline, save-per-field editing for a pad's properties. Replaces the former
//  modal edit sheet: each control commits its own `PUT /api/pads/:id` carrying
//  only the field that changed, so nothing else on the pad is touched.
//

import SwiftUI

private enum PadInlineCommitField: String {
    case language
    case owner
    case privacy
    case execution
}

@MainActor
private enum PadInlineCommitQueue {
    private static var tasks: [String: Task<Void, Never>] = [:]

    static func enqueue(padID: String,
                        field: PadInlineCommitField,
                        operation: @escaping @MainActor () async -> Void) {
        let key = "\(padID):\(field.rawValue)"
        let previous = tasks[key]
        tasks[key] = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }

            await operation()
        }
    }
}

extension PadDetailView {
    /// The editable pad properties, presented as labeled rows of inline controls.
    /// Title is edited in the header, notes are edited in their own long-form
    /// section, and language, owner, and the two flags live here.
    var propertyRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            propertyRow("Language") {
                Picker("", selection: languageBinding) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                        Text($0.coderPadLanguageDisplayName).tag($0)
                    }
                    // Keep the pad's current language selectable even when it
                    // isn't one of the common picker options.
                    if !CoderPadLanguages.pickerOptions.contains(draftLanguage) {
                        Text(draftLanguage.coderPadLanguageDisplayName).tag(draftLanguage)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            propertyRow("Owner") {
                SearchableOwnerPicker(ownerEmail: ownerBinding,
                                      users: orgUsers,
                                      keyOwnerEmail: keyOwnerEmail)
                    .fixedSize(horizontal: !isCompactPhone, vertical: false)
            }
            propertyRow("Private", alignment: .center) {
                Toggle("", isOn: privateBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            propertyRow("Execution enabled", alignment: .center) {
                Toggle("", isOn: executionBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        // Offline → read-only: disable the inline property editors so a field change
        // can't fire a doomed PUT against an unreachable server (#321).
        .disabled(isReadOnly)
        .task(id: pad.id) { await loadOrgUsers() }
    }

    /// The email of the user whose API key this detail view talks through, resolved
    /// from the view's own client identity rather than the globally current account:
    /// a standalone pad window or a merged row can belong to a non-current account,
    /// and reading the current account made the Owner picker's "Me" label follow
    /// account switches made elsewhere (#873). Falls back to the current account
    /// for clients that don't match a stored account byte-for-byte (e.g. mocks).
    private var keyOwnerEmail: String? {
        let match = AccountsStore.shared.accounts.first {
            $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == client.apiKey
                && $0.resolvedBaseURL == client.baseURL
        }
        return (match ?? AccountsStore.shared.currentAccount)?.userEmail
    }

    var propertiesCard: some View {
        DetailSection(title: "Properties", systemImage: "slider.horizontal.3") {
            propertyRows
        }
    }

    /// A labeled row pairing a property name with its inline control, matching the
    /// alignment of the read-only `LabeledRow`s in the Details section.
    ///
    /// Picker rows align to `.firstTextBaseline` so the label sits on the control's
    /// text baseline. Toggle rows pass `.center`: a switch has no meaningful text
    /// baseline, and the taller iOS switch otherwise leaves the label stranded at
    /// the top of the control rather than centered beside it.
    @ViewBuilder
    private func propertyRow(_ label: LocalizedStringKey,
                             alignment: VerticalAlignment = .firstTextBaseline,
                             @ViewBuilder control: () -> some View) -> some View {
        if isCompactPhone {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: alignment) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110, alignment: .leading)
                control()
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Bindings

    // Each binding reads its optimistic draft and, on a user change, updates the
    // draft immediately before kicking off the field's save. Reseeding a draft from
    // the pad (see `seedDrafts`) never goes through these setters, so there's no
    // commit loop when a save returns a refreshed pad.

    private var languageBinding: Binding<String> {
        Binding(get: { draftLanguage },
                set: { newValue in
                    draftLanguage = newValue
                    PadInlineCommitQueue.enqueue(padID: pad.id, field: .language) {
                        await commitLanguage(newValue)
                    }
                })
    }

    private var ownerBinding: Binding<String> {
        Binding(get: { draftOwner },
                set: { newValue in
                    draftOwner = newValue
                    PadInlineCommitQueue.enqueue(padID: pad.id, field: .owner) {
                        await commitOwner(newValue)
                    }
                })
    }

    private var privateBinding: Binding<Bool> {
        Binding(get: { draftIsPrivate },
                set: { newValue in
                    draftIsPrivate = newValue
                    PadInlineCommitQueue.enqueue(padID: pad.id, field: .privacy) {
                        await commitPrivate(newValue)
                    }
                })
    }

    private var executionBinding: Binding<Bool> {
        Binding(get: { draftExecution },
                set: { newValue in
                    draftExecution = newValue
                    PadInlineCommitQueue.enqueue(padID: pad.id, field: .execution) {
                        await commitExecution(newValue)
                    }
                })
    }

    // MARK: - Drafts

    /// Seeds every editable draft from the pad. Called on appear and whenever a
    /// different pad is shown.
    func seedDrafts() {
        draftLanguage = pad.language ?? "python3"
        draftOwner = pad.ownerEmail
        draftIsPrivate = pad.isPrivate ?? false
        draftExecution = pad.executionEnabled ?? true
    }

    /// Loads org members so the owner picker offers a searchable, named list. Falls
    /// back silently to free-text email entry when unavailable.
    private func loadOrgUsers() async {
        guard orgUsers.isEmpty, !client.apiKey.isEmpty else { return }

        if let org = try? await OrganizationCacheStore.shared.organization(via: client) {
            orgUsers = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        }
    }

    // MARK: - Per-field commits

    /// Commits an inline title rename, returning whether it saved so the self-owning
    /// title control can leave edit mode. On failure the control keeps its draft open
    /// for retry, so this path reports the error without reverting local field state.
    func commitTitle(_ newTitle: String) async -> Bool {
        guard newTitle != pad.title else { return true }

        do {
            try await client.updatePadWithoutRefetch(PadUpdate(id: pad.id, title: newTitle))
            AppRouter.padUpdated(optimisticPad(title: newTitle))
            return true
        } catch {
            mutateError = error.localizedDescription
            return false
        }
    }

    func commitLanguage(_ language: String) async {
        await save(PadUpdate(id: pad.id, language: language), optimistic: optimisticPad(language: language)) {
            draftLanguage = pad.language ?? "python3"
        }
    }

    func commitOwner(_ email: String) async {
        // .whitespacesAndNewlines, not .whitespaces: a pasted address can carry a
        // trailing newline, which would be sent to the server verbatim (#783).
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)

        // An empty owner makes the server resolve the pad to the key owner, whose email
        // can't be known locally — so this one edit keeps the authoritative re-GET
        // (`optimistic: nil`) rather than guessing the resolved owner.
        await save(PadUpdate(id: pad.id, ownerEmail: normalized.isEmpty ? nil : normalized), optimistic: nil) {
            draftOwner = pad.ownerEmail
        }
    }

    func commitPrivate(_ isPrivate: Bool) async {
        await save(PadUpdate(id: pad.id, isPrivate: isPrivate), optimistic: optimisticPad(isPrivate: isPrivate)) {
            draftIsPrivate = pad.isPrivate ?? false
        }
    }

    func commitExecution(_ enabled: Bool) async {
        await save(
            PadUpdate(id: pad.id, executionEnabled: enabled),
            optimistic: optimisticPad(executionEnabled: enabled)
        ) {
            draftExecution = pad.executionEnabled ?? true
        }
    }

    /// Commits private interviewer notes in place. The editor keeps its draft open
    /// on failure, so this path reports success instead of reverting local text.
    func commitNotes(_ text: String) async -> Bool {
        guard text != (pad.notes ?? "") else { return true }

        return await saveContent(PadUpdate(id: pad.id, notes: text), optimistic: optimisticPad(notes: text))
    }

    /// The pad with every immediately-committed draft applied (language, privacy,
    /// execution), plus whichever self-owning long-form field this commit changed.
    /// `title` is passed only by `commitTitle` — for the other fields the committed
    /// `pad.title` is kept so an as-yet-uncommitted title edit isn't pushed out early.
    /// Building from the full draft set (not just the one changed field) keeps
    /// concurrent rapid edits from clobbering each other, since those drafts are always
    /// the saved value (#376).
    private func optimisticPad(title: String? = nil,
                               language: String? = nil,
                               notes: String? = nil,
                               isPrivate: Bool? = nil,
                               executionEnabled: Bool? = nil) -> Pad {
        Pad(
            id: pad.id, title: title ?? pad.title, state: pad.state, ownerEmail: pad.ownerEmail,
            language: language ?? draftLanguage, participants: pad.participants, url: pad.url,
            playback: pad.playback, events: pad.events, notes: notes ?? pad.notes,
            drawing: pad.drawing, contents: pad.contents, history: pad.history,
            createdAt: pad.createdAt, updatedAt: pad.updatedAt, endedAt: pad.endedAt,
            type: pad.type, executionEnabled: executionEnabled ?? draftExecution,
            isPrivate: isPrivate ?? draftIsPrivate,
            activeEnvironmentID: pad.activeEnvironmentID, padEnvironmentIDs: pad.padEnvironmentIDs,
            questionIDs: pad.questionIDs, team: pad.team
        )
    }

    /// Sends a single-field content update and propagates the optimistic pad without
    /// the redundant re-GET (#376), returning whether it succeeded. On failure it
    /// surfaces the error; the inline editor keeps the unsaved text so nothing is lost.
    private func saveContent(_ body: PadUpdate, optimistic: Pad) async -> Bool {
        do {
            try await client.updatePadWithoutRefetch(body)
            AppRouter.padUpdated(optimistic)
            return true
        } catch {
            mutateError = error.localizedDescription
            return false
        }
    }

    /// Sends a single-field update and propagates the result. When `optimistic` is
    /// supplied the local copy is authoritative, so it PUTs without the redundant re-GET
    /// and propagates the optimistic pad (#376); otherwise (owner edits) it re-fetches
    /// the server's resolved state. On failure it surfaces the error and runs `revert`
    /// so the control never lies about what's saved.
    private func save(_ body: PadUpdate, optimistic: Pad?, revert: () -> Void) async {
        do {
            if let optimistic {
                try await client.updatePadWithoutRefetch(body)
                AppRouter.padUpdated(optimistic)
            } else {
                let updated = try await client.updatePad(body)
                AppRouter.padUpdated(updated)
            }
        } catch {
            mutateError = error.localizedDescription
            revert()
        }
    }
}
