//
//  QuestionDetailView+ContentCommits.swift
//  coderpad
//
//  Commits for the question's long-form content — description, solution, and the
//  candidate-instruction parts — split from QuestionDetailView+Edit.swift to keep
//  both files under the file-length limit.
//

import SwiftUI

nonisolated enum QuestionContentReadOutcome<Value> {
    case loaded(Value)
    case failed(String)
}

nonisolated enum QuestionContentRead {
    static func evaluate<Value>(load: () async throws -> Value) async throws -> QuestionContentReadOutcome<Value> {
        do {
            return try await .loaded(load())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failed(
                String(localized: "Could not check the latest question — \(error.localizedDescription)")
            )
        }
    }
}

extension QuestionDetailView {
    // MARK: - Long-form content commits

    // Description, solution, and each candidate-instruction part are edited inline
    // (see `InlineEditableText`). Each commit sends only its own field and reports
    // success back so the editor can close, or stay open on failure.

    func commitDescription(_ text: String, basedOn source: String) async -> Bool {
        guard text != (question.description ?? "") else { return true }

        return await serializedContentSave {
            guard await confirmUnchangedRemotely(source, \.description, field: .description) else { return false }

            return await saveContent(QuestionUpdate(id: question.id, description: text)) {
                optimisticQuestion(description: text)
            }
        }
    }

    func commitSolution(_ text: String, basedOn source: String) async -> Bool {
        guard text != (question.solution ?? "") else { return true }

        return await serializedContentSave {
            guard await confirmUnchangedRemotely(source, \.solution, field: .solution) else { return false }

            return await saveContent(QuestionUpdate(id: question.id, solution: text)) {
                optimisticQuestion(solution: text)
            }
        }
    }

    /// Which long-form field a conflict is about, so the message names it.
    enum LongFormField {
        case description
        case solution

        var changedElsewhereMessage: String {
            switch self {
            case .description:
                String(localized: "The description changed elsewhere. Review the latest version, then save again.")
            case .solution:
                String(localized: "The solution changed elsewhere. Review the latest version, then save again.")
            }
        }
    }

    /// Checks the server still holds the value this edit was based on, and reports
    /// the conflict if not.
    ///
    /// The modify endpoint has no ETag or version token, so "don't overwrite work
    /// you were never shown" can only be enforced by reading before writing. Without
    /// it, Save Anyway sent the local draft unconditionally: a colleague's newer
    /// description or solution, changed after this client last refreshed, was
    /// replaced with no sign anything had been lost (#2647).
    ///
    /// On conflict the fresh question is published, which drives the editor's
    /// existing "Changed elsewhere" banner — the user can read the latest version,
    /// merge by hand, and save again, and that second save passes this check
    /// because it is now based on what the server holds.
    ///
    /// An unreadable server is not treated as a conflict: blocking a save on a
    /// transient network failure would lose the user's work for no gain.
    private func confirmUnchangedRemotely(_ source: String,
                                          _ value: KeyPath<Question, String?>,
                                          field: LongFormField) async -> Bool {
        let outcome: QuestionContentReadOutcome<Question>
        do {
            guard let result = try await freshQuestion() else { return true }

            outcome = result
        } catch is CancellationError {
            return false
        } catch {
            assertionFailure("Question content read only throws cancellation: \(error)")
            return false
        }
        guard case let .loaded(fresh) = outcome else {
            if case let .failed(message) = outcome {
                editError = message
            }
            return false
        }
        guard (fresh[keyPath: value] ?? "") != source else { return true }

        editError = field.changedElsewhereMessage
        publish(fresh)
        return false
    }

    /// Runs a content save inside the per-question serial chain.
    ///
    /// Description, solution, and instruction saves all read the question, build a
    /// payload from it, and publish the result. Running two of those concurrently
    /// interleaved their read-modify-publish steps, so the later publish could
    /// drop the earlier edit from the merge base (#2649). One chain per question
    /// makes each save atomic with respect to the others.
    func serializedContentSave(_ operation: @escaping @MainActor () async -> Bool) async -> Bool {
        // Bind the queued work to the credentials it was created under: a save
        // chained behind an in-flight one can start after the account is removed
        // or re-keyed and must not fire through retired credentials (#2652).
        let enqueuedIdentity = AccountsStore.shared.account(matching: client)?.id
        return await QuestionContentSaveChain.run(
            key: "\(accountID?.uuidString ?? "current"):\(question.id)"
        ) {
            guard AccountsStore.shared.account(matching: client)?.id == enqueuedIdentity else { return false }

            return await operation()
        }
    }

    /// Commits one candidate-instruction part. The whole list is resent with only
    /// `index`'s text changed (each part keeps its `default_visible`), so editing
    /// part 2 onwards no longer collapses the parts into one (#334). An out-of-range
    /// index appends a new part, which is how the first part is added to a question
    /// that had none. Saves are serialized per question and each payload is built
    /// from the latest published question inside the serialized block, so parallel
    /// edits to two parts can't overwrite each other's text (#1188).
    func commitInstruction(at index: Int, original: String, text: String, basedOn source: String) async -> Bool {
        await serializedContentSave {
            await performCommitInstruction(at: index, original: original, text: text, basedOn: source)
        }
    }

    /// Resolves the edited part by its mount-time text as well as its captured
    /// index: another update can remove or reorder parts while an editor is open,
    /// and blindly appending the stale part at the end duplicated it instead of
    /// surfacing the conflict (#2648). Appending remains the deliberate path for
    /// adding a part to a question that had none.
    private func performCommitInstruction(at index: Int, original: String, text: String,
                                          basedOn source: String) async -> Bool {
        // Candidate instructions have no per-part endpoint: editing one part PUTs the
        // whole list. Built from the local copy, that payload silently reverted every
        // other part to whatever this client last saw — so a colleague's edit to part 3,
        // made while this editor was open, was erased by a save of part 1 (#2650).
        // Re-read the question first so the parts we aren't editing are the server's
        // current ones. This runs inside the per-question serialized block, so a
        // concurrent local save can't land between the read and the write (#1188).
        guard let base = await questionForContentSave() else { return false }

        var payloads = base.candidateInstructions.map {
            CandidateInstructionPayload(instructions: $0.instructions, defaultVisible: $0.defaultVisible)
        }
        // The part this editor is showing must still hold what the user believes
        // they're replacing, or Save Anyway would overwrite an edit they were never
        // shown (#2647). The index/`original` resolution below handles a part that
        // moved or vanished; this catches one whose text changed under it.
        if payloads.indices.contains(index), payloads[index].instructions != source,
           payloads[index].instructions == original || source != original {
            editError = String(
                localized: "Candidate instructions changed elsewhere. Review the latest parts, then save again."
            )
            publish(base)
            return false
        }
        if payloads.indices.contains(index), payloads[index].instructions == original {
            guard payloads[index].instructions != text else { return true }

            payloads[index].instructions = text
        } else if let moved = uniqueIndex(of: original, in: payloads) {
            guard payloads[moved].instructions != text else { return true }

            payloads[moved].instructions = text
        } else if index >= payloads.count, original.isEmpty {
            guard !text.isEmpty else { return true }

            payloads.append(CandidateInstructionPayload(instructions: text, defaultVisible: true))
        } else {
            editError = String(
                localized: "Candidate instructions changed elsewhere. Review the latest parts, then save again."
            )
            return false
        }
        return await saveContent(QuestionUpdate(id: question.id, candidateInstructions: payloads)) {
            optimisticQuestion(candidateInstructions: payloads)
        }
    }

    /// The question as the server currently has it. A missing API key retains the
    /// local-only preview path; network failures are explicit so saves cannot mistake
    /// an unreadable server for an unchanged question.
    func freshQuestion(id questionID: Int? = nil) async throws -> QuestionContentReadOutcome<Question>? {
        guard !client.apiKey.isEmpty else { return nil }

        return try await QuestionContentRead.evaluate {
            try await client.getQuestion(id: questionID ?? question.id)
        }
    }

    private func questionForContentSave() async -> Question? {
        do {
            guard let outcome = try await freshQuestion() else { return latestQuestion ?? question }

            switch outcome {
            case let .loaded(fresh):
                return fresh
            case let .failed(message):
                editError = message
                return nil
            }
        } catch is CancellationError {
            return nil
        } catch {
            assertionFailure("Question content read only throws cancellation: \(error)")
            return nil
        }
    }

    /// The single part whose text matches the edited part's mount-time text, or
    /// nil when the part vanished or the match is ambiguous.
    private func uniqueIndex(of original: String, in payloads: [CandidateInstructionPayload]) -> Int? {
        let matches = payloads.indices.filter { payloads[$0].instructions == original }
        return matches.count == 1 ? matches.first : nil
    }

    /// The question with the immediately-committed metadata drafts (language, type)
    /// applied, plus whichever long-form field this commit changed. As with the pad
    /// editor, building from the full saved-draft set keeps concurrent edits from
    /// clobbering each other; `title` is supplied only by `commitTitle` so an
    /// uncommitted title isn't pushed out early (#376).
    func optimisticQuestion(title: String? = nil, language: String? = nil, padType: String? = nil,
                            description: String? = nil, solution: String? = nil,
                            candidateInstructions: [CandidateInstructionPayload]? = nil) -> Question {
        let base = latestQuestion ?? question
        let optimisticPadType = padType ?? draftPadType
        return base.applying(
            title: title, language: language ?? draftLanguage,
            takeHome: optimisticPadType == "take-home", padType: optimisticPadType,
            description: description, solution: solution,
            candidateInstructions: candidateInstructions
        )
    }

    /// Sends a single-field content update and propagates the optimistic question
    /// without the redundant re-GET (#376), returning whether it succeeded. On failure
    /// it surfaces the error; the inline editor keeps the unsaved text so nothing is lost.
    func saveContent(_ body: QuestionUpdate, optimistic: () -> Question) async -> Bool {
        let targetQuestionID = question.id
        let targetAccountID = accountID
        let context = AccountClientContext(client: client, targetAccountID: targetAccountID)
        do {
            try await client.updateQuestionWithoutRefetch(body)
            guard inlineEditTargetIsCurrent(
                questionID: targetQuestionID,
                accountID: targetAccountID,
                context: context
            ) else {
                editError = BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed
                    .localizedDescription
                return false
            }

            publish(optimistic())
            await reconcileWithServer(
                questionID: targetQuestionID,
                accountID: targetAccountID,
                context: context
            )
            return true
        } catch is CancellationError {
            // As in `save`: a cancelled request is not a failed one (#4760).
            return false
        } catch {
            editError = error.localizedDescription
            return false
        }
    }

    /// Installs a question as the local merge base and broadcasts it, claiming the
    /// newest publish generation so a slower reconciliation can't undo it.
    private func publish(_ updated: Question) {
        questionPublishGeneration += 1
        latestQuestion = updated
        AppRouter.questionUpdated(updated, account: accountID)
    }

    /// Replaces the optimistic copy with the server's own, once the write has landed.
    ///
    /// The modify endpoint answers `{"status":"OK"}` with no question body, so
    /// anything the server normalizes on write — trimming, canonicalization,
    /// defaults it fills in — is invisible to this client. The optimistic copy then
    /// becomes the merge base for the next inline edit, which pushes those
    /// un-normalized values straight back out, undoing the server's own work (#2654).
    ///
    /// Running after the optimistic publish keeps the UI instant: the edit is already
    /// on screen, and this only corrects it. A failed read is ignored — the write
    /// itself succeeded, and the next list refresh reconciles anyway.
    private func reconcileWithServer(
        questionID targetQuestionID: Int,
        accountID targetAccountID: UUID?,
        context: AccountClientContext
    ) async {
        let generation = questionPublishGeneration
        let outcome: QuestionContentReadOutcome<Question>
        do {
            guard inlineEditTargetIsCurrent(
                questionID: targetQuestionID,
                accountID: targetAccountID,
                context: context
            ), let result = try await freshQuestion(id: targetQuestionID) else { return }

            outcome = result
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Question content read only throws cancellation: \(error)")
            return
        }
        guard case let .loaded(fresh) = outcome else {
            if case let .failed(message) = outcome {
                editError = message
            }
            return
        }

        // A newer edit landed while this read was in flight, so the server copy is
        // already out of date; publishing it would revert what the user just typed.
        guard generation == questionPublishGeneration,
              inlineEditTargetIsCurrent(
                  questionID: targetQuestionID,
                  accountID: targetAccountID,
                  context: context
              ) else { return }

        publish(fresh)
    }

    /// Sends a single-field update and propagates the optimistic question without the
    /// redundant re-GET (#376). On failure it surfaces the error and runs `revert` to
    /// snap the field back to the server's value, so the control never lies about what's
    /// saved.
    func save(_ body: QuestionUpdate, optimistic: () -> Question, revert: () -> Void) async {
        let targetQuestionID = question.id
        let targetAccountID = accountID
        let context = AccountClientContext(client: client, targetAccountID: targetAccountID)
        do {
            try await client.updateQuestionWithoutRefetch(body)
            guard inlineEditTargetIsCurrent(
                questionID: targetQuestionID,
                accountID: targetAccountID,
                context: context
            ) else {
                editError = BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed
                    .localizedDescription
                return
            }

            publish(optimistic())
            await reconcileWithServer(
                questionID: targetQuestionID,
                accountID: targetAccountID,
                context: context
            )
        } catch is CancellationError {
            // The view was torn down, the pad switched, or the task cancelled mid-request.
            // The PUT may well have been delivered and applied, so reverting would make the
            // control show a value the server no longer holds, and the banner would report
            // a failure that did not happen (#4760). Every other mutation path in the app
            // already special-cases this.
            return
        } catch {
            editError = error.localizedDescription
            revert()
        }
    }
}
