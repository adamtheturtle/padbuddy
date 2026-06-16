//
//  MenuBarView+Logic.swift
//  coderpad
//

import AppKit
import SwiftUI

extension MenuBarView {
    /// A one-line summary of the account's pad quota for the header, or `nil`
    /// when quota hasn't loaded yet (or the API doesn't report it).
    var quotaSummary: String? {
        guard let quota else { return nil }
        if quota.unlimited == true { return String(localized: "Unlimited pads") }
        if let remaining = quota.padsRemaining {
            if let limit = quota.billingCyclePadLimit {
                return String(localized: "\(remaining) of \(limit) pads remaining")
            }
            return String(localized: "\(remaining) pads remaining")
        }
        if let used = quota.padsUsed { return String(localized: "\(used) pads used") }
        return nil
    }

    /// Opens the main window and switches it to `section`. The section is durable
    /// navigation state, so this works whether or not the window is already open.
    func go(_ section: AppSection) {
        AppNavigation.shared.show(section)
        openMain()
    }

    func padLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        let language = pad.language.flatMap { $0.isEmpty ? nil : " · \($0.languageDisplayName)" } ?? ""
        return "\(title)\(language)"
    }

    /// Label for a pad in the "Recent Activity" sub-menu, trailing the title with a
    /// relative "updated" time since recency is the point of that section.
    func activityLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        guard let updated = pad.informativeUpdatedAt else { return title }
        return "\(title) · \(updated.formatted(.relative(presentation: .named)))"
    }

    /// Opens the main window on the Questions list with `question` selected, the
    /// same route the sidebar uses for a favorite question.
    func openQuestion(_ question: Question) {
        AppNavigation.shared.showQuestions(QuestionsRequest(selectQuestionID: question.id))
        openMain()
    }

    /// Pads owned by the account's configured email, if the user set one in Settings.
    /// Otherwise falls back to the most-frequent owner email in the fetched list, since
    /// the CoderPad API doesn't tell us which user the key belongs to.
    var myPads: [Pad] {
        let mineOnly: [Pad]
        if let mine = store.currentAccount?.userEmail, !mine.isEmpty {
            mineOnly = pads.filter { $0.ownerEmail == mine }
        } else {
            let owners = pads
                .map(\.ownerEmail)
                .filter { !$0.isEmpty }
                .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            if let mine = owners.max(by: { $0.value < $1.value })?.key {
                mineOnly = pads.filter { $0.ownerEmail == mine }
            } else {
                mineOnly = pads
            }
        }
        // Optionally narrow to active interviews when the user enables it in Settings.
        return startedOnly ? mineOnly.filter { $0.status == .active } : mineOnly
    }

    /// Questions for the "New Pad from Question" submenu, with favorites floated to
    /// the top (keeping the underlying most-recently-updated order within each
    /// group) so the user's starred questions lead the one-click pad list.
    func questionsForMenu(favoriteIDs: Set<Int>) -> [Question] {
        guard !favoriteIDs.isEmpty else { return questions }
        return questions.filter { favoriteIDs.contains($0.id) }
            + questions.filter { !favoriteIDs.contains($0.id) }
    }

    func createPad(_ body: PadCreate, account: Account) async {
        let client = account.makeClient()
        do {
            let pad = try await client.createPad(body)
            if let url = pad.webURL {
                BrowserSettings.openExternally(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openMain() {
        AppActivator.bringToFront()
        openWindow(id: "main")
    }

    func load(account: Account) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let client = account.makeClient()
        do {
            async let padsTask = client.listPads()
            async let qsTask = client.listQuestions()
            async let quotaTask = client.quota()
            // Write fetched results straight into the shared caches (no clearing
            // first): the menu — and every other view reading these stores — keeps
            // showing the previous data until the fresh data lands, so switching
            // accounts shows the new account's cache rather than a blank "Loading…".
            let fetched = try await padsTask
            PadsCacheStore.shared.set(account.id, pads: fetched)
            if let fetchedQuestions = try? await qsTask {
                QuestionsCacheStore.shared.set(account.id, questions: fetchedQuestions)
            }
            if let fetchedQuota = try? await quotaTask {
                QuotaCacheStore.shared.set(account.id, quota: fetchedQuota)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
