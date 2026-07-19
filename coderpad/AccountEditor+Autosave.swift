//
//  AccountEditor+Autosave.swift
//  coderpad
//

import Foundation

extension AccountEditor {
    /// Save-gated fields that differ from the latest successful autosave. Appearance
    /// changes are excluded because their dedicated callback persists them immediately.
    var hasUnsavedLiveChanges: Bool {
        let normalized = draft.normalizedForStorage
        return normalized.name != persistedDraft.name
            || normalized.apiKey != persistedDraft.apiKey
            || normalized.userEmail != persistedDraft.userEmail
            || normalized.baseURL != persistedDraft.baseURL
            || normalized.screenApiKey != persistedDraft.screenApiKey
            || normalized.screenRegion != persistedDraft.screenRegion
    }

    /// Saved accounts are managed like settings: changes autosave in the embedded
    /// editor instead of waiting for an explicit Save button. Adding a new account stays
    /// modal and explicit, because it is a multi-step validation flow.
    var commitsLive: Bool {
        embedded && isEditing
    }

    /// Schedules a debounced autosave for saved-account edits. Credential changes still
    /// respect `canSave`, so a changed API key or server URL waits for validation before
    /// the stored account is updated.
    func commitLiveEdit() {
        guard commitsLive else { return }

        liveCommitTask?.cancel()
        liveCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            persistLiveEditIfPossible()
        }
    }

    func descriptionChanged() {
        nameEditGeneration &+= 1
        commitLiveEdit()
    }

    /// Persists the current draft when autosave is allowed and the draft is in a valid
    /// saveable state. Called after the debounce and when the editor disappears, so a
    /// quick navigation away does not drop the latest valid edit.
    func persistLiveEditIfPossible() {
        guard commitsLive, canSave else { return }

        // The account must still exist. A debounced autosave can fire after the user
        // deleted the account (or dismissed the editor and then deleted it), and
        // `onSave` on a removed id re-creates it from the stale draft (#2191).
        guard AccountsStore.shared.accounts.contains(where: { $0.id == draft.id }) else { return }

        finalizeNameIfNeeded()
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let saved = draft.normalizedForStorage
        persistedDraft = saved
        onSave(saved)
    }

    /// Persists the draft now, cancelling any debounced autosave first.
    ///
    /// An explicit Save did not cancel the pending task, so an older scheduled draft
    /// could land afterwards and overwrite the newer fields the user had just saved
    /// (#2192).
    func saveNow() {
        liveCommitTask?.cancel()
        liveCommitTask = nil
        finalizeNameIfNeeded()
        let saved = draft.normalizedForStorage
        persistedDraft = saved
        onSave(saved)
    }
}
