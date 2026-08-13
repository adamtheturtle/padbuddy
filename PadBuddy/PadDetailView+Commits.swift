//
//  PadDetailView+Commits.swift
//  coderpad
//
//  The pad detail view's per-field commits, split from PadDetailView+Edit.swift
//  to keep both files under the file-length limit.
//

import SwiftUI

nonisolated enum PadNotesPreflightOutcome<Value> {
    case current(Value)
    case conflict(Value)
    case failed(String)
}

nonisolated enum PadNotesPreflight {
    static func evaluate<Value>(
        source: String,
        load: () async throws -> Value,
        notes: (Value) -> String
    ) async throws -> PadNotesPreflightOutcome<Value> {
        do {
            let value = try await load()
            return notes(value) == source ? .current(value) : .conflict(value)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let message = String(
                localized: "Could not check the latest interviewer notes — \(error.localizedDescription)"
            )
            return .failed(message)
        }
    }
}

extension PadDetailView {
    // MARK: - Per-field commits

    /// Commits an inline title rename, returning whether it saved so the self-owning
    /// title control can leave edit mode. On failure the control keeps its draft open
    /// for retry, so this path reports the error without reverting local field state.
    func commitTitle(_ newTitle: String) async -> Bool {
        // Trimmed before sending: a whitespace-only rename slips past the
        // empty-title fallbacks and renders blank list, sidebar, and browser
        // labels (#1800).
        let newTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newTitle != pad.title else { return true }

        do {
            try await client.updatePadWithoutRefetch(PadUpdate(id: pad.id, title: newTitle))
            let optimistic = optimisticPad(title: newTitle)
            latestPad = optimistic
            AppRouter.padUpdated(optimistic, account: owningAccountID)
            return true
        } catch {
            mutateError = error.localizedDescription
            return false
        }
    }

    func commitLanguage(_ language: String) async {
        await save(PadUpdate(id: pad.id, language: language),
                   optimistic: { optimisticPad(language: language) },
                   revert: { draftLanguage = pad.language ?? "python3" })
    }

    func commitOwner(_ email: String) async {
        // Trimmed (a pasted address can carry a trailing newline, #783) and with
        // the domain lowercased so one mailbox has one stored spelling (#1941).
        let normalized = EmailValidation.normalized(email)

        // A free-typed owner must at least look like an email before it's sent:
        // the control is presented as an owner selector, and posting arbitrary
        // text produced server errors or surprising owner assignments (#1189).
        // Empty stays allowed — the server resolves it to the key owner.
        guard normalized.isEmpty || EmailValidation.isPlausibleAddress(normalized) else {
            mutateError = String(localized: "“\(normalized)” is not a valid email address.")
            draftOwner = pad.ownerEmail
            return
        }

        // An empty owner makes the server resolve the pad to the key owner, whose email
        // can't be known locally — so this one edit keeps the authoritative re-GET
        // (`optimistic: nil`) rather than guessing the resolved owner.
        await save(PadUpdate(id: pad.id, ownerEmail: normalized.isEmpty ? nil : normalized),
                   optimistic: nil,
                   revert: { draftOwner = pad.ownerEmail })
    }

    func commitPrivate(_ isPrivate: Bool) async {
        await save(PadUpdate(id: pad.id, isPrivate: isPrivate),
                   optimistic: { optimisticPad(isPrivate: isPrivate) },
                   revert: { draftIsPrivate = pad.isPrivate ?? false })
    }

    func commitExecution(_ enabled: Bool) async {
        await save(PadUpdate(id: pad.id, executionEnabled: enabled),
                   optimistic: { optimisticPad(executionEnabled: enabled) },
                   revert: { draftExecution = pad.executionEnabled ?? true })
    }

    /// Commits private interviewer notes in place. The editor keeps its draft open
    /// on failure, so this path reports success instead of reverting local text.
    func commitNotes(_ text: String, basedOn source: String) async -> Bool {
        guard text != (pad.notes ?? "") else { return true }

        // The modify endpoint has no ETag, so "don't overwrite work you were never
        // shown" can only be enforced by reading before writing: Save Anyway
        // otherwise replaced a colleague's newer notes with no sign anything was
        // lost (#2647). If this safety read fails, keep the draft open and report the
        // failure rather than overwriting server notes whose current value is unknown.
        let outcome: PadNotesPreflightOutcome<Pad>
        do {
            outcome = try await PadNotesPreflight.evaluate(
                source: source,
                load: { try await client.getPad(id: pad.id) },
                notes: { $0.notes ?? "" }
            )
        } catch is CancellationError {
            return false
        } catch {
            assertionFailure("Pad notes preflight only throws cancellation: \(error)")
            return false
        }
        switch outcome {
        case .current:
            break
        case let .conflict(fresh):
            notesConflict = PadNotesConflict(local: text, server: fresh.notes ?? "")
            latestPad = fresh
            AppRouter.padUpdated(fresh, account: owningAccountID)
            return false
        case let .failed(message):
            mutateError = message
            return false
        }

        return await saveContent(PadUpdate(id: pad.id, notes: text)) { optimisticPad(notes: text) }
    }

    /// The pad with every immediately-committed draft applied (language, privacy,
    /// execution), plus whichever self-owning long-form field this commit changed.
    /// `title` is passed only by `commitTitle` — for the other fields the committed
    /// `pad.title` is kept so an as-yet-uncommitted title edit isn't pushed out early.
    /// Building from the full draft set (not just the one changed field) keeps
    /// concurrent rapid edits from clobbering each other, since those drafts are always
    /// the saved value (#376). The untouched fields come from the latest published
    /// pad (`latestPad`, kept fresh by `draftSync`), never this view's older
    /// snapshot: a concurrent refresh or another window's edit to owner, notes, or
    /// state must not be replaced by stale copies of fields this save never sent
    /// (#1186).
    private func optimisticPad(title: String? = nil,
                               language: String? = nil,
                               notes: String? = nil,
                               isPrivate: Bool? = nil,
                               executionEnabled: Bool? = nil) -> Pad {
        let base = latestPad ?? pad
        return Pad(
            id: base.id, title: title ?? base.title, state: base.state, ownerEmail: base.ownerEmail,
            language: language ?? draftLanguage, participants: base.participants, url: base.url,
            playback: base.playback, events: base.events, notes: notes ?? base.notes,
            drawing: base.drawing, contents: base.contents, history: base.history,
            createdAt: base.createdAt, updatedAt: base.updatedAt, endedAt: base.endedAt,
            type: base.type, executionEnabled: executionEnabled ?? draftExecution,
            isPrivate: isPrivate ?? draftIsPrivate,
            activeEnvironmentID: base.activeEnvironmentID, padEnvironmentIDs: base.padEnvironmentIDs,
            questionIDs: base.questionIDs, team: base.team
        )
    }

    /// Sends a single-field content update and propagates the optimistic pad without
    /// the redundant re-GET (#376), returning whether it succeeded. On failure it
    /// surfaces the error; the inline editor keeps the unsaved text so nothing is lost.
    /// `optimistic` is a closure evaluated after the request returns, so the published
    /// pad merges this field into the then-latest base rather than a pre-request
    /// snapshot (#1186).
    private func saveContent(_ body: PadUpdate, optimistic: () -> Pad) async -> Bool {
        do {
            try await client.updatePadWithoutRefetch(body)
            let optimistic = optimistic()
            latestPad = optimistic
            AppRouter.padUpdated(optimistic, account: owningAccountID)
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
    /// so the control never lies about what's saved. See `saveContent` for why
    /// `optimistic` is deferred (#1186).
    private func save(_ body: PadUpdate, optimistic: (() -> Pad)?, revert: () -> Void) async {
        do {
            if let optimistic {
                try await client.updatePadWithoutRefetch(body)
                let optimistic = optimistic()
                latestPad = optimistic
                AppRouter.padUpdated(optimistic, account: owningAccountID)
            } else {
                let updated = try await client.updatePad(body)
                latestPad = updated
                AppRouter.padUpdated(updated, account: owningAccountID)
            }
        } catch {
            mutateError = error.localizedDescription
            revert()
        }
    }
}
