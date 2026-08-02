//
//  CommandPalette+Builder.swift
//  coderpad
//
//  Builds the command palette's candidate list (#526) from the shared stores: commands,
//  sections, accounts, and the cached pads and questions. Split out
//  of CommandPalette.swift to keep each file focused.
//

import CommandPaletteKit
import Foundation
import SwiftUI

/// Assembles the palette's candidate list from the shared stores. Ordered Commands,
/// Sections, Accounts, then Pads and Questions, so an empty query reads sensibly and ties
/// in scoring keep that order.
@MainActor
enum CommandPaletteBuilder {
    struct PadPaletteText {
        let title: String
        let subtitle: String?
        let searchText: String
    }

    private struct DynamicAccumulator {
        var newPads: [PaletteResult] = []
        var content: [PaletteResult] = []
        var remainingPads = CommandPaletteBuilder.maximumPadResults
        var remainingQuestions = CommandPaletteBuilder.maximumQuestionResults
        var remainingNewPads = CommandPaletteBuilder.maximumNewPadResults
    }

    private struct DynamicAccountOptions {
        let canCreate: Bool
        let showContentAccount: Bool
        let showCreateAccount: Bool
        let favoriteIDs: Set<Int>
    }

    static func build() -> [PaletteResult] {
        let dynamic = dynamicResults()
        var results: [PaletteResult] = []
        results += commands()
        results += sections()
        results += dynamic.newPads
        results += accounts()
        results += dynamic.content
        return results
    }

    /// Builds navigation and "New Pad from Question" rows in one cache traversal.
    /// Two separate passes previously read, deduplicated, and interpolated every
    /// cached question independently each time the palette opened (#2134).
    private static func dynamicResults() -> (newPads: [PaletteResult], content: [PaletteResult]) {
        let store = AccountsStore.shared
        let isOffline = NetworkMonitor.shared.isOffline
        let accounts = store.isMergedView ? store.mergeableAccounts : [store.currentAccount].compactMap(\.self)
        let creatableAccounts = accounts.filter {
            AppCreationAvailability.canCreate(account: $0, isOffline: isOffline)
        }
        let creatableIDs = Set(creatableAccounts.map(\.id))
        let showContentAccount = accounts.count > 1
        let showCreateAccount = creatableAccounts.count > 1

        var accumulator = DynamicAccumulator()
        for account in accounts {
            let canCreate = creatableIDs.contains(account.id)
            let options = DynamicAccountOptions(
                canCreate: canCreate,
                showContentAccount: showContentAccount,
                showCreateAccount: showCreateAccount,
                favoriteIDs: canCreate ? Set(FavoriteQuestionsStore.shared.favorites(account: account.id)) : []
            )
            appendPads(for: account, showAccount: showContentAccount,
                       accumulator: &accumulator)
            appendQuestions(for: account, options: options, accumulator: &accumulator)
        }
        return (accumulator.newPads, accumulator.content)
    }

    private static func appendPads(
        for account: Account, showAccount: Bool,
        accumulator: inout DynamicAccumulator
    ) {
        let clientIdentity = account.makeClient().taskIdentity
        let pads = uniquePads(PadsCacheStore.shared.get(account.id), limit: accumulator.remainingPads)
        accumulator.remainingPads -= pads.count
        for pad in pads {
            let text = padPaletteText(pad, account: showAccount ? account.name : nil)
            accumulator.content.append(PaletteResult(
                id: "pad.\(account.id.uuidString).\(pad.id)", kind: .pad,
                title: text.title, subtitle: text.subtitle, systemImage: "doc.text",
                searchText: text.searchText
            ) { activatePad(pad.id, in: account.id, clientIdentity: clientIdentity) })
        }
    }

    private static func appendQuestions(
        for account: Account, options: DynamicAccountOptions,
        accumulator: inout DynamicAccumulator
    ) {
        let clientIdentity = account.makeClient().taskIdentity
        let limit = max(accumulator.remainingQuestions,
                        options.canCreate ? accumulator.remainingNewPads : 0)
        for question in uniqueQuestions(QuestionsCacheStore.shared.get(account.id), limit: limit) {
            let text = questionPaletteText(question)
            if accumulator.remainingQuestions > 0 {
                accumulator.content.append(PaletteResult(
                    id: "question.\(account.id.uuidString).\(question.id)", kind: .question,
                    title: text.title,
                    subtitle: subtitle(account: options.showContentAccount ? account.name : nil,
                                       detail: text.language),
                    systemImage: "questionmark.bubble",
                    searchText: sanitizedRemoteText("\(text.title) \(text.language)", limit: 320)
                ) { activateQuestion(question.id, in: account.id, clientIdentity: clientIdentity) })
                accumulator.remainingQuestions -= 1
            }
            guard options.canCreate, accumulator.remainingNewPads > 0 else { continue }

            accumulator.newPads.append(PaletteResult(
                id: "new-pad-from-question.\(account.id.uuidString).\(question.id)", kind: .command,
                title: sanitizedRemoteText(String(localized: "New Pad from \(text.title)")),
                subtitle: subtitle(account: options.showCreateAccount ? account.name : nil,
                                   detail: String(localized: "Create a pad from this question")),
                systemImage: "plus.rectangle.on.folder",
                searchText: sanitizedRemoteText("New Pad from question \(text.title)", limit: 320),
                onlyWhenSearching: !options.favoriteIDs.contains(question.id)
            ) {
                NewPadFromQuestionRunner.createAndOpen(
                    question: question, accountID: account.id, clientIdentity: clientIdentity
                )
            })
            accumulator.remainingNewPads -= 1
        }
    }

    private static func commands() -> [PaletteResult] {
        let creationSubtitle = NetworkMonitor.shared.isOffline
            ? String(localized: "Unavailable while offline")
            : String(localized: "Create a pad")
        let questionCreationSubtitle = NetworkMonitor.shared.isOffline
            ? String(localized: "Unavailable while offline")
            : String(localized: "Create a question")
        return [
            PaletteResult(
                id: "command.new-pad",
                kind: .command,
                title: "New Pad",
                subtitle: creationSubtitle,
                systemImage: "plus.square",
                searchText: "New Pad create"
            ) { performNewPad() },
            PaletteResult(
                id: "command.new-question",
                kind: .command,
                title: "New Question",
                subtitle: questionCreationSubtitle,
                systemImage: "plus.bubble",
                searchText: "New Question create"
            ) { performNewQuestion() },
            PaletteResult(
                id: "command.open-by-url",
                kind: .command,
                title: "Open Pad by URL…",
                subtitle: "Open a pad from its link",
                systemImage: "link",
                searchText: "Open Pad by URL link"
            ) { AppRouter.requestOpenPadByURL() },
            PaletteResult(
                id: "command.reload",
                kind: .command,
                title: "Reload",
                subtitle: "Refresh the current section",
                systemImage: "arrow.clockwise",
                searchText: "Reload refresh"
            ) { AppRouter.requestReload() }
        ]
    }

    private static func performNewPad() {
        guard announceIfOffline() == false else { return }

        AppNavigation.shared.showPads(PadsRequest(startCreating: true))
    }

    private static func performNewQuestion() {
        guard announceIfOffline() == false else { return }

        AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
    }

    private static func announceIfOffline() -> Bool {
        guard NetworkMonitor.shared.isOffline else { return false }

        AccessibilityNotification.Announcement(String(localized: "Unavailable while offline")).post()
        return true
    }

    private static func sections() -> [PaletteResult] {
        AppSection.navigable.map { section in
            let meta = paletteMeta(section)
            return PaletteResult(
                id: "section.\(section.rawValue)",
                kind: .section,
                title: meta.label,
                subtitle: "Go to \(meta.label)",
                systemImage: meta.icon,
                searchText: meta.label
            ) { AppNavigation.shared.show(section) }
        }
    }

    private static func accounts() -> [PaletteResult] {
        let store = AccountsStore.shared
        // Only worth offering as a switch target when there's more than one account.
        guard store.accounts.count > 1 else { return [] }

        return switchableAccounts(store.accounts, limit: maximumAccountResults).map { account in
            PaletteResult(
                id: "account.\(account.id.uuidString)",
                kind: .account,
                title: sanitizedRemoteText(account.name, fallback: "Account"),
                subtitle: sanitizedRemoteText(account.userEmail, fallback: "Switch account"),
                systemImage: "person.crop.circle",
                searchText: accountSearchText(account)
            ) {
                // Leave All Accounts mode too: `isMergedView` is derived from
                // `showAllAccounts`, so setting only the current id leaves the
                // merged view showing and the switch reads as a no-op (#987).
                // Mirrors every other switch site (account footer, menu bar).
                AccountsStore.shared.showAllAccounts = false
                AccountsStore.shared.currentAccountID = account.id
            }
        }
    }

    static func accountSearchText(_ account: Account) -> String {
        sanitizedRemoteText(account.name, fallback: "Account")
    }

    static func padTitle(title: String, id: String) -> String {
        sanitizedRemoteText(title, fallback: sanitizedRemoteText(id, fallback: "Pad"))
    }

    static func padPaletteText(_ pad: Pad, account: String?) -> PadPaletteText {
        let title = padTitle(title: pad.title, id: pad.id)
        return PadPaletteText(title: title,
                              subtitle: subtitle(account: account, detail: nil),
                              searchText: sanitizedRemoteText(title, limit: 320))
    }

    private static func questionPaletteText(_ question: Question) -> (title: String, language: String) {
        (sanitizedRemoteText(question.displayTitle, fallback: "#\(question.id)"),
         sanitizedRemoteText(question.language))
    }

    static func sanitizedRemoteText(_ raw: String?, fallback: String = "", limit: Int = 160) -> String {
        let normalized = (raw ?? "")
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String((normalized.isEmpty ? fallback : normalized).prefix(limit))
    }

    /// Switches to `account` (only if it isn't already current - per-org question ids
    /// collide, so the owning account must be selected first, exactly as the Spotlight
    /// result path does) and selects the pad once its list has it. In merged mode the
    /// account travels with the request instead, mirroring `showQuestion(id:account:)`:
    /// pad slugs are only unique per server, so two custom servers can share one and
    /// the bare slug could select the wrong account's row (#758).
    /// Joins an optional account name and an optional detail into one subtitle line.
    private static func subtitle(account: String?, detail: String?) -> String? {
        let parts = [account, detail]
            .compactMap { sanitizedRemoteText($0).isEmpty ? nil : sanitizedRemoteText($0, limit: 80) }
        return parts.isEmpty ? nil : sanitizedRemoteText(parts.joined(separator: " · "))
    }

    /// The label and SF Symbol for each navigable section. Mirrors the sidebar's own
    /// `sectionMeta` (kept here as plain strings since the palette scores against them).
    private static func paletteMeta(_ section: AppSection) -> (label: String, icon: String) {
        switch section {
        case .pads: (String(localized: "Pads"), "doc.text")
        case .questions: (String(localized: "Questions"), "questionmark.bubble")
        case .organization: (String(localized: "Organization"), "building.2")
        case .quota: (String(localized: "Quota"), "gauge.with.dots.needle.67percent")
        case .screen: (String(localized: "Screen"), "person.crop.rectangle.stack")
        }
    }
}
