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
    private static var running: [String: Task<Void, Never>] = [:]
    private static var pending: [String: @MainActor () async -> Void] = [:]

    /// Serializes saves per account + pad + field. The key carries the owning
    /// account: pad slugs collide across custom servers, so a process-global
    /// slug key made unrelated accounts' saves wait on each other and retained
    /// the other window's state (#1181). While a save is in flight only the
    /// newest queued value is kept, so rapid Picker/Toggle churn sends at most
    /// one trailing PUT with the final choice instead of replaying every
    /// intermediate value (#1185). Entries are removed as their work drains, so
    /// completed tasks and their captured views aren't retained for the life of
    /// the process (#1182).
    static func enqueue(account: UUID?,
                        client: CoderPadClient,
                        padID: String,
                        field: PadInlineCommitField,
                        operation: @escaping @MainActor () async -> Void) {
        let key = "\(account?.uuidString ?? "current"):\(padID):\(field.rawValue)"
        // Bind the queued work to the credentials it was created under: a save
        // queued behind an in-flight one can start after its account is removed
        // or re-keyed, and firing it then would PUT through retired credentials
        // and publish the result into stale state (#2651). Mock/test clients
        // match no stored account (nil) and stay allowed while that holds.
        let enqueuedIdentity = AccountsStore.shared.account(matching: client)?.id
        let guarded: @MainActor () async -> Void = {
            guard AccountsStore.shared.account(matching: client)?.id == enqueuedIdentity else { return }

            await operation()
        }
        guard running[key] == nil else {
            pending[key] = guarded
            return
        }

        run(key: key, operation: guarded)
    }

    private static func run(key: String, operation: @escaping @MainActor () async -> Void) {
        running[key] = Task { @MainActor in
            await operation()
            running[key] = nil
            if let next = pending.removeValue(forKey: key) {
                run(key: key, operation: next)
            }
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
            if let restricted = pad.restrictInterviewerAccess {
                padMetadataRow(label: "Interviewer access", value: restricted ? "Restricted" : "Standard")
            }
        }
        // Offline → read-only: disable the inline property editors so a field change
        // can't fire a doomed PUT against an unreachable server (#321).
        .disabled(isReadOnly)
        // Keyed to the pad, the client identity, and connectivity: a re-keyed
        // account must not keep exposing the previous org's member list (#1191),
        // and a load that failed offline retries when connectivity returns
        // instead of leaving free-text entry for the rest of the view's life (#1190).
        .task(id: "\(pad.id)|\(clientIdentity)|\(isReadOnly)") { await loadOrgUsers() }
    }

    /// The email of the user whose API key this detail view talks through, resolved
    /// from the view's own client identity rather than the globally current account:
    /// a standalone pad window or a merged row can belong to a non-current account,
    /// and reading the current account made the Owner picker's "Me" label follow
    /// account switches made elsewhere (#873). Falls back to the current account
    /// for clients that don't match a stored account byte-for-byte (e.g. mocks).
    private var keyOwnerEmail: String? {
        let store = AccountsStore.shared
        return (store.account(matching: client) ?? store.currentAccount)?.userEmail
    }

    /// A labeled row pairing a property name with its inline control. The overview
    /// uses stacked rows on every platform so long values and controls do not force
    /// narrow label columns or awkward wrapping in the detail pane.
    private func propertyRow(_ label: LocalizedStringKey,
                             alignment _: VerticalAlignment = .firstTextBaseline,
                             @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            control()
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    PadInlineCommitQueue.enqueue(account: owningAccountID, client: client,
                                                 padID: pad.id, field: .language) {
                        await commitLanguage(newValue)
                    }
                })
    }

    private var ownerBinding: Binding<String> {
        Binding(get: { draftOwner },
                set: { newValue in
                    draftOwner = newValue
                    PadInlineCommitQueue.enqueue(account: owningAccountID, client: client,
                                                 padID: pad.id, field: .owner) {
                        await commitOwner(newValue)
                    }
                })
    }

    private var privateBinding: Binding<Bool> {
        Binding(get: { draftIsPrivate },
                set: { newValue in
                    draftIsPrivate = newValue
                    PadInlineCommitQueue.enqueue(account: owningAccountID, client: client,
                                                 padID: pad.id, field: .privacy) {
                        await commitPrivate(newValue)
                    }
                })
    }

    private var executionBinding: Binding<Bool> {
        Binding(get: { draftExecution },
                set: { newValue in
                    draftExecution = newValue
                    PadInlineCommitQueue.enqueue(account: owningAccountID, client: client,
                                                 padID: pad.id, field: .execution) {
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

    /// A stable identity for the view's client, so the org-member list can be
    /// keyed to the credentials it was fetched through (#1191).
    private var clientIdentity: String {
        "\(client.baseURL.absoluteString)|\(client.apiKey.hashValue)"
    }

    /// Loads org members so the owner picker offers a searchable, named list. Falls
    /// back silently to free-text email entry when unavailable; the keyed `.task`
    /// above re-runs it (a retry) whenever the pad, client identity, or
    /// connectivity changes (#1190).
    private func loadOrgUsers() async {
        guard !client.apiKey.isEmpty else { return }

        // A list fetched through different credentials is another org's directory:
        // drop it rather than offering the previous account's members while the
        // reload runs (#1191). A same-client transient failure keeps the existing
        // list, which is still current.
        if orgUsersSource != clientIdentity {
            orgUsers = []
        }
        if let org = try? await OrganizationCacheStore.shared.organization(via: client) {
            orgUsers = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
            orgUsersSource = clientIdentity
        }
    }
}
