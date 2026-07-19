//
//  QuestionDetailView+ContentCommits.swift
//  coderpad
//
//  Commits for the question's long-form content — description, solution, and the
//  candidate-instruction parts — split from QuestionDetailView+Edit.swift to keep
//  both files under the file-length limit.
//

import SwiftUI

extension QuestionDetailView {
    // MARK: - Long-form content commits

    // Description, solution, and each candidate-instruction part are edited inline
    // (see `InlineEditableText`). Each commit sends only its own field and reports
    // success back so the editor can close, or stay open on failure.

    func commitDescription(_ text: String) async -> Bool {
        guard text != (question.description ?? "") else { return true }

        return await saveContent(QuestionUpdate(id: question.id, description: text)) {
            optimisticQuestion(description: text)
        }
    }

    func commitSolution(_ text: String) async -> Bool {
        guard text != (question.solution ?? "") else { return true }

        return await saveContent(QuestionUpdate(id: question.id, solution: text)) {
            optimisticQuestion(solution: text)
        }
    }

    /// Commits one candidate-instruction part. The whole list is resent with only
    /// `index`'s text changed (each part keeps its `default_visible`), so editing
    /// part 2 onwards no longer collapses the parts into one (#334). An out-of-range
    /// index appends a new part, which is how the first part is added to a question
    /// that had none. Saves are serialized per question and each payload is built
    /// from the latest published question inside the serialized block, so parallel
    /// edits to two parts can't overwrite each other's text (#1188).
    func commitInstruction(at index: Int, original: String, text: String) async -> Bool {
        // Same credential binding as the metadata queue: an instruction save
        // chained behind an in-flight one can start after the account is
        // removed or re-keyed and must not fire through retired credentials (#2652).
        let enqueuedIdentity = AccountsStore.shared.account(matching: client)?.id
        return await QuestionInstructionSaveChain.run(
            key: "\(accountID?.uuidString ?? "current"):\(question.id)"
        ) {
            guard AccountsStore.shared.account(matching: client)?.id == enqueuedIdentity else { return false }

            return await performCommitInstruction(at: index, original: original, text: text)
        }
    }

    /// Resolves the edited part by its mount-time text as well as its captured
    /// index: another update can remove or reorder parts while an editor is open,
    /// and blindly appending the stale part at the end duplicated it instead of
    /// surfacing the conflict (#2648). Appending remains the deliberate path for
    /// adding a part to a question that had none.
    private func performCommitInstruction(at index: Int, original: String, text: String) async -> Bool {
        // Candidate instructions have no per-part endpoint: editing one part PUTs the
        // whole list. Built from the local copy, that payload silently reverted every
        // other part to whatever this client last saw — so a colleague's edit to part 3,
        // made while this editor was open, was erased by a save of part 1 (#2650).
        // Re-read the question first so the parts we aren't editing are the server's
        // current ones. This runs inside the per-question serialized block, so a
        // concurrent local save can't land between the read and the write (#1188).
        let base = await freshQuestion() ?? latestQuestion ?? question
        var payloads = base.candidateInstructions.map {
            CandidateInstructionPayload(instructions: $0.instructions, defaultVisible: $0.defaultVisible)
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

    /// The question as the server currently has it, or `nil` when it can't be read.
    ///
    /// Callers fall back to the local copy on `nil`: a transient read failure should
    /// not block a save the user asked for, it only means the save proceeds with the
    /// weaker guarantee it had before.
    func freshQuestion() async -> Question? {
        guard !client.apiKey.isEmpty else { return nil }

        return try? await client.getQuestion(id: question.id)
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
        do {
            try await client.updateQuestionWithoutRefetch(body)
            publish(optimistic())
            await reconcileWithServer()
            return true
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
    private func reconcileWithServer() async {
        let generation = questionPublishGeneration
        guard let fresh = await freshQuestion() else { return }

        // A newer edit landed while this read was in flight, so the server copy is
        // already out of date; publishing it would revert what the user just typed.
        guard generation == questionPublishGeneration else { return }

        publish(fresh)
    }

    /// Sends a single-field update and propagates the optimistic question without the
    /// redundant re-GET (#376). On failure it surfaces the error and runs `revert` to
    /// snap the field back to the server's value, so the control never lies about what's
    /// saved.
    func save(_ body: QuestionUpdate, optimistic: () -> Question, revert: () -> Void) async {
        do {
            try await client.updateQuestionWithoutRefetch(body)
            publish(optimistic())
            await reconcileWithServer()
        } catch {
            editError = error.localizedDescription
            revert()
        }
    }
}
