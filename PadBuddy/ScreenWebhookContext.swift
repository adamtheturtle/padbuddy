//
//  ScreenWebhookContext.swift
//  coderpad
//

import Foundation

struct ScreenWebhookContext: Hashable {
    let accountID: UUID
    let clientIdentity: ClientTaskIdentity

    func matches(accountID: UUID, clientIdentity: ClientTaskIdentity) -> Bool {
        self.accountID == accountID && self.clientIdentity == clientIdentity
    }
}

@MainActor
enum ScreenWebhookLoadIdentity {
    static func isCurrent(
        _ generation: Int,
        currentGeneration: Int,
        requestedContext: ScreenWebhookContext,
        currentContext: ScreenWebhookContext
    ) -> Bool {
        generation == currentGeneration && requestedContext == currentContext
    }
}

nonisolated enum ScreenWebhookMutationLifetime {
    static func shouldCancelOnDisappear(mutationWasIssued: Bool) -> Bool {
        !mutationWasIssued
    }
}

nonisolated enum ScreenWebhookDraftIdentity {
    static func canApply(
        loadRevision: Int, currentRevision: Int,
        draftAtLoad: String, loadedBaseline: String
    ) -> Bool {
        loadRevision == currentRevision && draftAtLoad == loadedBaseline
    }
}
