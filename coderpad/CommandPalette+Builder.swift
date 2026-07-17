//
//  CommandPalette+Builder.swift
//  coderpad
//
//  Builds the command palette's candidate list (#526) from the shared stores: commands,
//  sections, accounts, and the cached pads and questions. Split out
//  of CommandPalette.swift to keep each file focused.
//

import CommandPaletteKit
import SwiftUI

/// Assembles the palette's candidate list from the shared stores. Ordered Commands,
/// Sections, Accounts, then Pads and Questions, so an empty query reads sensibly and ties
/// in scoring keep that order.
@MainActor
enum CommandPaletteBuilder {
    static func build() -> [PaletteResult] {
        var results: [PaletteResult] = []
        results += commands()
        results += sections()
        results += newPadFromQuestions()
        results += accounts()
        results += padsAndQuestions()
        return results
    }

    /// "New Pad from <Question>" entries - the one-click pad the menu-bar extra offers,
    /// surfaced in the palette too (#534). Every cached question gets one, so a pad can be
    /// started from any question, not just favourites (#537); the non-favourite ones are
    /// marked `onlyWhenSearching` so the empty-query list stays short and favourites-first.
    private static func newPadFromQuestions() -> [PaletteResult] {
        let store = AccountsStore.shared
        let accounts = store.isMergedView ? store.mergeableAccounts : [store.currentAccount].compactMap(\.self)
        let showAccount = accounts.count > 1

        var results: [PaletteResult] = []
        for account in accounts {
            let favoriteIDs = Set(FavoriteQuestionsStore.shared.favorites(account: account.id))

            for question in QuestionsCacheStore.shared.get(account.id) {
                results.append(PaletteResult(
                    id: "new-pad-from-question.\(account.id.uuidString).\(question.id)",
                    kind: .command,
                    title: "New Pad from \(question.displayTitle)",
                    subtitle: subtitle(account: showAccount ? account.name : nil,
                                       detail: "Create a pad from this question"),
                    systemImage: "plus.rectangle.on.folder",
                    searchText: "New Pad from question \(question.displayTitle)",
                    onlyWhenSearching: !favoriteIDs.contains(question.id)
                ) { NewPadFromQuestionRunner.createAndOpen(question: question, account: account) })
            }
        }
        return results
    }

    private static func commands() -> [PaletteResult] {
        [
            PaletteResult(
                id: "command.new-pad",
                kind: .command,
                title: "New Pad",
                subtitle: "Create a pad",
                systemImage: "plus.square",
                searchText: "New Pad create"
            ) { AppNavigation.shared.showPads(PadsRequest(startCreating: true)) },
            PaletteResult(
                id: "command.new-question",
                kind: .command,
                title: "New Question",
                subtitle: "Create a question",
                systemImage: "plus.bubble",
                searchText: "New Question create"
            ) { AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true)) },
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

        return store.accounts.map { account in
            PaletteResult(
                id: "account.\(account.id.uuidString)",
                kind: .account,
                title: account.name,
                subtitle: account.userEmail.isEmpty ? "Switch account" : account.userEmail,
                systemImage: "person.crop.circle",
                searchText: "\(account.name) \(account.userEmail)"
            ) { AccountsStore.shared.currentAccountID = account.id }
        }
    }

    private static func padsAndQuestions() -> [PaletteResult] {
        let store = AccountsStore.shared
        let accounts = store.isMergedView ? store.mergeableAccounts : [store.currentAccount].compactMap(\.self)
        let showAccount = accounts.count > 1

        var results: [PaletteResult] = []
        for account in accounts {
            for pad in PadsCacheStore.shared.get(account.id) {
                let title = pad.title.isEmpty ? pad.id : pad.title
                results.append(PaletteResult(
                    id: "pad.\(account.id.uuidString).\(pad.id)",
                    kind: .pad,
                    title: title,
                    subtitle: subtitle(account: showAccount ? account.name : nil, detail: pad.ownerEmail),
                    systemImage: "doc.text",
                    searchText: "\(title) \(pad.ownerEmail)"
                ) { jump(toPad: pad.id, in: account.id) })
            }
            for question in QuestionsCacheStore.shared.get(account.id) {
                results.append(PaletteResult(
                    id: "question.\(account.id.uuidString).\(question.id)",
                    kind: .question,
                    title: question.displayTitle,
                    subtitle: subtitle(account: showAccount ? account.name : nil, detail: question.language),
                    systemImage: "questionmark.bubble",
                    searchText: "\(question.displayTitle) \(question.language ?? "")"
                ) { jump(toQuestion: question.id, in: account.id) })
            }
        }
        return results
    }

    /// Switches to `account` (only if it isn't already current - per-org question ids
    /// collide, so the owning account must be selected first, exactly as the Spotlight
    /// result path does) and selects the pad once its list has it.
    private static func jump(toPad id: String, in account: UUID) {
        if AccountsStore.shared.currentAccountID != account,
           AccountsStore.shared.accounts.contains(where: { $0.id == account }) {
            AccountsStore.shared.currentAccountID = account
        }
        AppNavigation.shared.showFavoritePad(id: id)
    }

    private static func jump(toQuestion id: Int, in account: UUID) {
        AppNavigation.shared.showQuestion(id: id, account: account)
    }

    /// Joins an optional account name and an optional detail into one subtitle line.
    private static func subtitle(account: String?, detail: String?) -> String? {
        let parts = [account, detail?.isEmpty == true ? nil : detail].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The label and SF Symbol for each navigable section. Mirrors the sidebar's own
    /// `sectionMeta` (kept here as plain strings since the palette scores against them).
    private static func paletteMeta(_ section: AppSection) -> (label: String, icon: String) {
        switch section {
        case .pads: ("Pads", "doc.text")
        case .questions: ("Questions", "questionmark.bubble")
        case .organization: ("Organization", "building.2")
        case .quota: ("Quota", "gauge.with.dots.needle.67percent")
        case .screen: ("Screen", "person.crop.rectangle.stack")
        }
    }
}
