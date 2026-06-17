//
//  CoderPadAPI+OptimisticEdit.swift
//  coderpad
//
//  Memberwise initializers and focused copy helpers that let the inline per-field
//  editors apply a saved change to their local model and skip the redundant re-GET
//  the modify endpoints would otherwise force (#376). The live API replies only
//  `{"status":"OK"}` to a PUT, so without these the views re-fetch the whole
//  resource after every single field commit; with them the optimistic local state is
//  authoritative and the server is reconciled on the next list refresh.
//
//  `Pad`/`Question` carry custom decoding inits and so synthesize no memberwise init;
//  these explicit ones (in an extension, leaving the decoding path untouched) make a
//  modified copy possible without a network round-trip.
//

import Foundation

extension Pad {
    /// Full memberwise initializer, alongside the decoding `init(from:)`.
    init(
        id: String, title: String, state: String, ownerEmail: String, language: String?,
        participants: [String], url: String, playback: String?, events: String?, notes: String?,
        drawing: String?, contents: String?, history: String?, createdAt: Date?, updatedAt: Date?,
        endedAt: Date?, type: String?, executionEnabled: Bool?, isPrivate: Bool?,
        activeEnvironmentID: Int?, padEnvironmentIDs: [Int], questionIDs: [Int], team: PadTeam?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.ownerEmail = ownerEmail
        self.language = language
        self.participants = participants
        self.url = url
        self.playback = playback
        self.events = events
        self.notes = notes
        self.drawing = drawing
        self.contents = contents
        self.history = history
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
        self.type = type
        self.executionEnabled = executionEnabled
        self.isPrivate = isPrivate
        self.activeEnvironmentID = activeEnvironmentID
        self.padEnvironmentIDs = padEnvironmentIDs
        self.questionIDs = questionIDs
        self.team = team
    }

    /// A copy with the inline-editable fields overridden (`nil` keeps the current
    /// value). `updatedAt` is intentionally left as-is and reconciled on the next
    /// refresh. Owner is deliberately excluded: clearing it asks the server to resolve
    /// the pad to the key owner, whose email can't be known locally, so that one edit
    /// keeps the authoritative re-GET (see `PadDetailView.save`).
    func applying(
        title: String? = nil, language: String? = nil,
        isPrivate: Bool? = nil, executionEnabled: Bool? = nil
    ) -> Pad {
        Pad(
            id: id, title: title ?? self.title, state: state, ownerEmail: ownerEmail,
            language: language ?? self.language, participants: participants, url: url,
            playback: playback, events: events, notes: notes, drawing: drawing,
            contents: contents, history: history, createdAt: createdAt, updatedAt: updatedAt,
            endedAt: endedAt, type: type, executionEnabled: executionEnabled ?? self.executionEnabled,
            isPrivate: isPrivate ?? self.isPrivate, activeEnvironmentID: activeEnvironmentID,
            padEnvironmentIDs: padEnvironmentIDs, questionIDs: questionIDs, team: team
        )
    }
}

extension Question {
    /// Full memberwise initializer, alongside the decoding `init(from:)`.
    init(
        id: Int, title: String, ownerEmail: String, language: String?, description: String?,
        shared: Bool?, used: Int?, takeHome: Bool?, testCasesEnabled: Bool?, solution: String?,
        padType: String?, isDraft: Bool?, authorName: String?, organizationName: String?,
        contents: String?, contentsForTestCases: String?, publicTakeHomeSettingID: Int?,
        customFiles: [QuestionCustomFile], testCases: [QuestionTestCase], createdAt: Date?,
        updatedAt: Date?, candidateInstructions: [CandidateInstruction]
    ) {
        self.id = id
        self.title = title
        self.ownerEmail = ownerEmail
        self.language = language
        self.description = description
        self.shared = shared
        self.used = used
        self.takeHome = takeHome
        self.testCasesEnabled = testCasesEnabled
        self.solution = solution
        self.padType = padType
        self.isDraft = isDraft
        self.authorName = authorName
        self.organizationName = organizationName
        self.contents = contents
        self.contentsForTestCases = contentsForTestCases
        self.publicTakeHomeSettingID = publicTakeHomeSettingID
        self.customFiles = customFiles
        self.testCases = testCases
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.candidateInstructions = candidateInstructions
    }

    /// A copy with the inline-editable metadata and long-form content overridden
    /// (`nil` keeps the current value). `updatedAt` is left as-is and reconciled on the
    /// next refresh. `candidateInstructions` is supplied as the encode-only payload the
    /// editor already builds, mapped onto the decoded model shape.
    func applying(
        title: String? = nil, language: String? = nil, takeHome: Bool? = nil, padType: String? = nil,
        description: String? = nil, solution: String? = nil,
        candidateInstructions newInstructions: [CandidateInstructionPayload]? = nil
    ) -> Question {
        Question(
            id: id, title: title ?? self.title, ownerEmail: ownerEmail,
            language: language ?? self.language, description: description ?? self.description,
            shared: shared, used: used, takeHome: takeHome ?? self.takeHome,
            testCasesEnabled: testCasesEnabled, solution: solution ?? self.solution,
            padType: padType ?? self.padType, isDraft: isDraft, authorName: authorName,
            organizationName: organizationName, contents: contents,
            contentsForTestCases: contentsForTestCases,
            publicTakeHomeSettingID: publicTakeHomeSettingID, customFiles: customFiles,
            testCases: testCases, createdAt: createdAt, updatedAt: updatedAt,
            candidateInstructions: newInstructions.map { payloads in
                payloads.map {
                    CandidateInstruction(instructions: $0.instructions, defaultVisible: $0.defaultVisible)
                }
            } ?? candidateInstructions
        )
    }
}

extension CandidateInstruction {
    /// Memberwise initializer, alongside the decoding `init(from:)`, so the question
    /// content editor can build instruction parts for an optimistic update (#376).
    init(instructions: String, defaultVisible: Bool) {
        self.instructions = instructions
        self.defaultVisible = defaultVisible
    }
}
