//
//  InterviewTemplates.swift
//  coderpad
//
//  Interview templates (#525): a saved "favorite question + language (+ optional pad
//  title)" so the common case of running the same kind of interview repeatedly is a
//  single action. Templates are small per-account user config, so they persist as
//  UserDefaults JSON keyed by account id - the same pattern as `FavoriteQuestionsStore`.
//  Running a template creates a pad seeded from its question (overriding the language)
//  and opens it, honoring the in-app/external browser preference, and falls back to the
//  in-app create sheet when the API call can't complete (offline). Templates are listed
//  in the Cmd-K command palette and managed from the Pad menu.
//

import Foundation
import os
import SwiftUI

/// A saved interview template: a question to seed from, the language to run it in, and an
/// optional fixed pad title. `name` is the user-facing label shown in menus and the
/// command palette; `questionTitle` is captured so the management UI can show what the
/// template points at without loading the question.
struct InterviewTemplate: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var questionID: Int
    var questionTitle: String
    var language: String
    /// An explicit pad title to use; when nil/empty the pad inherits the question's title.
    var titlePattern: String?

    init(
        name: String,
        questionID: Int,
        questionTitle: String,
        language: String,
        titlePattern: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.questionID = questionID
        self.questionTitle = questionTitle
        self.language = language
        self.titlePattern = titlePattern
    }
}

/// Per-account store of interview templates, persisted as UserDefaults JSON. `@Observable`
/// so the management sheet and command palette react to changes. Mirrors
/// `FavoriteQuestionsStore`'s shape so the persistence is consistent and predictable.
@MainActor
@Observable
final class InterviewTemplatesStore {
    static let shared = InterviewTemplatesStore()

    private var byAccount: [UUID: [InterviewTemplate]]
    private static let key = "interviewTemplates.v1"
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    private static let cloudKey = "interviewTemplates.cloud.v1"
    private var cloudObserver: (any NSObjectProtocol)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [InterviewTemplate]].self, from: data) {
            byAccount = decoded
        } else {
            byAccount = [:]
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            // Delivered on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated {
                guard key == Self.cloudKey else { return }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// The templates saved for `account`, in saved order. Empty for a nil/unknown account.
    func templates(account: UUID?) -> [InterviewTemplate] {
        guard let account else { return [] }

        return byAccount[account] ?? []
    }

    func add(_ template: InterviewTemplate, account: UUID) {
        byAccount[account, default: []].append(template)
        save()
    }

    /// Replaces the template with the same id (no-op if it isn't there).
    func update(_ template: InterviewTemplate, account: UUID) {
        guard let index = byAccount[account]?.firstIndex(where: { $0.id == template.id }) else { return }

        byAccount[account]?[index] = template
        save()
    }

    func remove(id: UUID, account: UUID) {
        byAccount[account]?.removeAll { $0.id == id }
        save()
    }

    /// Drops every template for an account, called when the account itself is removed so
    /// no orphaned config lingers.
    func remove(account: UUID) {
        byAccount[account] = nil
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode interview templates: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current templates up to iCloud, keyed by each account's stable sync
    /// id. No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = CloudSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud templates and merges them in, unioning by template id so an edit
    /// on one device never forks the entry. Called once accounts have loaded and on every
    /// external iCloud change. No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [InterviewTemplate]].self, from: data) else { return }

        let merged = CloudSyncMerge.mergeArrays(cloud: cloud, into: byAccount) { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        } id: { $0.id }
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}

/// Runs a template: creates a pad seeded from its question (overriding the language and,
/// if set, the title) and opens it. Kept separate from the store so the store stays pure
/// state and this owns the API + window side effects.
@MainActor
enum InterviewTemplateRunner {
    /// Creates a pad from `template` under `account` and opens it, honoring the
    /// in-app/external browser preference. On failure (offline, transient API error) it
    /// falls back to the in-app create sheet seeded with the template's question, so the
    /// action is never silently lost - the same recovery `createPadInBrowser` uses.
    static func createAndOpen(_ template: InterviewTemplate, account: Account) {
        var body = PadCreate()
        body.questionID = template.questionID
        body.language = template.language
        if let custom = template.titlePattern, !custom.isEmpty { body.title = custom }

        open(body, account: account, fallbackQuestionID: template.questionID)
    }

    /// Creates a pad directly from `question` (its default language) and opens it - the
    /// same one-click "New Pad from Question" the menu-bar extra offers, surfaced in the
    /// main-window menu and the command palette too (#534).
    static func createAndOpen(question: Question, account: Account) {
        open(PadCreate.fromQuestion(question), account: account, fallbackQuestionID: question.id)
    }

    /// Creates a pad from `body` and opens it, honoring the in-app/external browser
    /// preference. On failure (offline, transient API error) it falls back to the in-app
    /// create sheet seeded with the question, so the action is never silently lost.
    private static func open(_ body: PadCreate, account: Account, fallbackQuestionID: Int?) {
        let client = account.makeClient()
        let accountID = account.id
        Task { @MainActor in
            do {
                let pad = try await client.createPad(body)
                guard let url = pad.webURL else { return }

                AppActivator.bringToFront()
                if BrowserSettings.openLinksIn == .external {
                    BrowserSettings.openExternally(url)
                } else {
                    AppRouter.requestOpenPadInBrowser(url)
                }
            } catch {
                AppNavigation.shared.routeNewPad(account: accountID.uuidString, seedQuestionID: fallbackQuestionID)
            }
        }
    }
}
