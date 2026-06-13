//
//  coderpadApp.swift
//  coderpad
//

import AppKit
import CoreSpotlight
import SwiftUI

let copyrightLine = "Copyright © 2026 Adam Dangoor"

/// Shows the app's custom About panel, populated with version, build, credits,
/// and copyright. Shared by the app menu and the menu-bar extra so both surface
/// the same information.
func showAboutPanel() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        NSApplication.AboutPanelOptionKey.applicationName: "CoderPad",
        NSApplication.AboutPanelOptionKey.applicationVersion: version,
        NSApplication.AboutPanelOptionKey.version: "Build \(build)",
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyrightLine
    ])
}

extension Notification.Name {
    static let reloadRequested = Notification.Name("coderpad.reloadRequested")
    static let openPadByURLRequested = Notification.Name("coderpad.openPadByURLRequested")
    static let padUpdated = Notification.Name("coderpad.padUpdated")
    static let padDeleted = Notification.Name("coderpad.padDeleted")
    static let questionUpdated = Notification.Name("coderpad.questionUpdated")
    static let questionDeleted = Notification.Name("coderpad.questionDeleted")
    static let openSettingsRequested = Notification.Name("coderpad.openSettingsRequested")
    static let openPadInBrowserRequested = Notification.Name("coderpad.openPadInBrowserRequested")
    static let bulkEndStartedRequested = Notification.Name("coderpad.bulkEndStartedRequested")
    static let bulkMakePrivateRequested = Notification.Name("coderpad.bulkMakePrivateRequested")
}

/// `userInfo` keys for the question mutation notifications.
enum QuestionNotificationKey {
    /// The owning account's `UUID`, so combined-view consumers scope a
    /// `.questionUpdated` / `.questionDeleted` to the right account when two
    /// accounts share a per-org question id. Absent means "account unknown" and
    /// consumers fall back to their prior, id-only behavior.
    static let account = "coderpad.account"
}

/// A one-shot request for the Pads pane to apply when it next appears. Unlike a
/// transient notification, it survives until the destination view actually mounts
/// and consumes it — so "switch to Pads, then filter/search/create" works even
/// when PadsView isn't on screen at the moment the request is made.
struct PadsRequest: Equatable {
    var ownerEmail: String?
    var search: String?
    var startCreating = false
    /// A saved search to apply wholesale when the pane appears. Carries the full
    /// filter set so picking a saved search from the sidebar reproduces exactly
    /// what saving it captured — the same as tapping its in-pane chip.
    var applySearch: NamedSearch?
}

/// The Questions-pane equivalent of `PadsRequest`.
struct QuestionsRequest: Equatable {
    var search: String?
    var startCreating = false
    /// A saved search to apply wholesale when the pane appears (see `PadsRequest`).
    var applySearch: NamedSearch?
    /// A favorite question to select when the pane appears, addressed by id since
    /// the sidebar that routes it holds favorite ids, not the loaded `Question`s.
    var selectQuestionID: Int?
}

/// Single source of truth for the visible section and any pending request queued
/// for a section's pane. Centralizing this removes the ordering hazard of posting
/// "switch section" and "apply filter" as two separate notifications: the target
/// pane may not be mounted yet when the second one fires, so it would be dropped.
/// Here the request is durable state the pane reads on appear.
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    private init() {}

    var section: AppSection = .pads

    /// Consumed and cleared by PadsView when it appears or this value changes.
    var padsRequest: PadsRequest?
    /// Consumed and cleared by QuestionsView when it appears or this value changes.
    var questionsRequest: QuestionsRequest?

    /// The live filter signature of each list, republished by its pane whenever its
    /// filters change (and on appear). The sidebar compares these against the
    /// suggested and saved rows to highlight whichever search is currently applied,
    /// falling back to the plain "Pads"/"Questions" row when nothing matches. Kept
    /// here rather than inferred from `padsRequest`/`questionsRequest` because those
    /// are transient one-shot requests, while this must track every in-pane filter
    /// edit (a chip toggle, a menu change) so the sidebar highlight never lies about
    /// what's on screen. Compared by filter fields only; `name`/`id` are ignored.
    var padsFilter = NamedSearch(name: "")
    var questionsFilter = NamedSearch(name: "")

    /// The live "Mine" preset state of each combined ("All Accounts") list,
    /// republished by `MergedPadsView`/`MergedQuestionsView` so the sidebar can
    /// honestly highlight its "My Pads"/"My Questions" rows in merged mode. The
    /// combined views own their filters locally rather than through
    /// `padsFilter`/`padsRequest` (their "Mine" is per-account ownership, not a
    /// single owner email), so a one-shot `…Request` lets the sidebar set the
    /// preset; the view consumes and clears it, then republishes the result here.
    /// Mirrors the padsFilter/padsRequest split the single-account panes use.
    var mergedPadsMineOnly = false
    var mergedPadsMineRequest: Bool?
    var mergedQuestionsMineOnly = false
    var mergedQuestionsMineRequest: Bool?

    /// A question id whose detail pane should immediately create a pad and open it
    /// inline (the in-pane browser), matching the detail view's "New Pad" button.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView when it appears or this value changes.
    var createPadForQuestionID: Int?

    /// A question id whose detail pane should immediately present its edit sheet.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView, mirroring `createPadForQuestionID`.
    var editQuestionID: Int?

    /// A question id whose detail pane should immediately present its delete
    /// confirmation. Routed (rather than deleting inline) so the context menu and
    /// the detail view share the same confirmation step before the irreversible delete.
    var deleteQuestionID: Int?

    /// A pad id whose detail pane should immediately present its edit sheet. The
    /// pad counterpart to `editQuestionID`, set by the Pad menu command and
    /// consumed/cleared by `PadDetailView` when it appears or this value changes.
    var editPadID: String?

    /// A pad id whose detail pane should immediately present its "End Interview"
    /// confirmation. Routed (rather than ending inline) so the menu command and the
    /// detail view share the same confirmation step before the live session is ended.
    var endPadID: String?

    /// A pad id whose detail pane should immediately present its delete
    /// confirmation — the pad counterpart to `deleteQuestionID`, never deleting
    /// without that confirmation step.
    var deletePadID: String?

    /// A pad id whose detail pane should open its session playback, routed from
    /// the Pad menu's "Watch Playback" command so it honors the same in-app vs.
    /// external browser preference as the detail view's Watch button.
    var watchPlaybackPadID: String?

    /// A pad id whose detail pane should run its "Save Code" panel, routed from
    /// the Pad menu so the menu command and the toolbar button share the same
    /// save logic (and the same knowledge of which files have loaded).
    var saveCodePadID: String?

    /// A question id whose detail pane should toggle its favorite state, routed
    /// from the Question menu's Favorite command — the counterpart to the
    /// detail view's toolbar star.
    var toggleFavoriteQuestionID: Int?

    /// A pad id requested by the "Open Pad by ID" App Intent. Durable state (rather
    /// than a transient notification) so the request survives a cold launch where the
    /// intent fires before any view is listening. Consumed/cleared by ContentView.
    var openPadID: String?

    /// Switch to a section with no pending request.
    func show(_ section: AppSection) {
        self.section = section
    }

    /// Switch to Pads and queue a request for the list to apply on appear.
    func showPads(_ request: PadsRequest = PadsRequest()) {
        section = .pads
        padsRequest = request
    }

    /// Switch to Questions and queue a request for the list to apply on appear.
    func showQuestions(_ request: QuestionsRequest = QuestionsRequest()) {
        section = .questions
        questionsRequest = request
    }

    /// Switch to the list that owns `search` and apply it, routing a sidebar
    /// saved-search tap through the same per-pane `apply` the in-list chips use.
    func applySavedSearch(_ search: NamedSearch, kind: SavedSearchKind) {
        switch kind {
        case .pads: showPads(PadsRequest(applySearch: search))
        case .questions: showQuestions(QuestionsRequest(applySearch: search))
        }
    }

    /// Toggle a combined list's "Mine" preset from the sidebar, switching to that
    /// list first. Targets the opposite of the last-published state so repeated taps
    /// flip it; the merged view consumes the request, applies it, and republishes.
    func toggleMergedMine(kind: SavedSearchKind) {
        switch kind {
        case .pads: section = .pads; mergedPadsMineRequest = !mergedPadsMineOnly
        case .questions: section = .questions; mergedQuestionsMineRequest = !mergedQuestionsMineOnly
        }
    }

    /// Switch to a combined list's plain, unfiltered root, clearing its "Mine"
    /// preset — the merged counterpart to tapping the "Pads"/"Questions" row.
    func showMergedRoot(kind: SavedSearchKind) {
        switch kind {
        case .pads: section = .pads; mergedPadsMineRequest = false
        case .questions: section = .questions; mergedQuestionsMineRequest = false
        }
    }

    /// Switch to Questions and select the favorite question with `id` once the
    /// list has it, so a sidebar favorite opens straight into its detail pane.
    func showFavoriteQuestion(id: Int) {
        showQuestions(QuestionsRequest(selectQuestionID: id))
    }

    /// Queue a pad id to open in the in-app browser, consumed by ContentView.
    func openPad(id: String) {
        openPadID = id
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        // The Dock badge defaults to on; register it before anything reads the value
        // so the preference and its Settings toggle agree on the unset case.
        UserDefaults.standard.register(defaults: [DockBadge.Key.showActivePads: true])
        // Honor the "Hide Dock icon" preference from the moment the app launches.
        GeneralSettings.applyDockVisibility()
        // Seed the badge from whatever pads are already cached; it refreshes again as
        // each account's list loads.
        DockBadge.refresh()
    }
}

@main
struct CoderpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Drives the app-wide light/dark override; nil follows the system appearance.
    @AppStorage(GeneralSettings.Key.appearance) private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup("CoderPad", id: "main") {
            ContentView()
                // Width floor is owned by `MainSplit`, derived from the live column
                // minimums (and enforced via the sidebar's auto-collapse) rather
                // than a hardcoded number here.
                .frame(minHeight: 540)
                .preferredColorScheme(appearance.colorScheme)
                // Open the pad/question behind a tapped Spotlight result.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    if let padID = SpotlightIndexer.padID(fromItemIdentifier: id) {
                        AppNavigation.shared.openPad(id: padID)
                    } else if let questionID = SpotlightIndexer.questionID(fromItemIdentifier: id) {
                        AppNavigation.shared.showFavoriteQuestion(id: questionID)
                    }
                }
                // Open a pad tapped in the Recent Pads widget (coderpad://pad/<id>).
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1100, height: 720)
        .commands {
            appCommands
            FindCommands()
            ViewCommands()
            PadCommands()
            QuestionCommands()
            WindowCommands()
        }

        WindowGroup("Pad Browser", id: "pad-browser", for: URL.self) { $url in
            if let url {
                PadBrowserView(url: url)
                    .frame(minWidth: 900, minHeight: 700)
                    .navigationTitle(url.host ?? "Pad")
                    .preferredColorScheme(appearance.colorScheme)
            } else {
                // The system can restore this window without a persisted URL; show a
                // placeholder rather than a blank, zero-content window.
                ContentUnavailableView("No Pad", systemImage: "macwindow",
                                       description: Text("Open a pad to view it here."))
                    .frame(minWidth: 900, minHeight: 700)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }

        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CoderPad") { showAbout() }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Pad…") {
                AppNavigation.shared.showPads(PadsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command])
            Button("New Question…") {
                AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open Pad by URL…") {
                NotificationCenter.default.post(name: .openPadByURLRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
            Divider()
            Button("Reload") {
                NotificationCenter.default.post(name: .reloadRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        CommandMenu("Go") {
            Button("Pads") { post(.pads) }.keyboardShortcut("1", modifiers: [.command])
            Button("Questions") { post(.questions) }.keyboardShortcut("2", modifiers: [.command])
            Button("Organization") { post(.organization) }.keyboardShortcut("3", modifiers: [.command])
            Button("Quota") { post(.quota) }.keyboardShortcut("4", modifiers: [.command])
            Divider()
            Button("Next Section") { cycleSection(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Section") { cycleSection(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
            Link("Get API Key", destination: CoderPadLinks.apiSettings)
            Divider()
            Link("Send Feedback…", destination: CoderPadLinks.feedbackMailto)
        }
    }

    private func post(_ section: AppSection) {
        AppNavigation.shared.show(section)
    }

    /// Routes a `coderpad://` deep link from the widget. `coderpad://pad/<id>` opens
    /// that pad in the in-app browser; `coderpad://pads` just brings the Pads list
    /// forward. Reuses the same durable navigation as the Spotlight and intent paths.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "coderpad" else { return }
        switch url.host {
        case "pad":
            let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty { AppNavigation.shared.openPad(id: id) }
        case "pads":
            AppNavigation.shared.show(.pads)
        default:
            break
        }
    }

    /// Moves the visible section forward (`+1`) or back (`-1`) through the fixed
    /// section order, wrapping at the ends. Backs the Go menu's Next/Previous items.
    private func cycleSection(by delta: Int) {
        let order: [AppSection] = [.pads, .questions, .organization, .quota]
        let current = AppNavigation.shared.section
        let index = order.firstIndex(of: current) ?? 0
        let count = order.count
        let next = order[((index + delta) % count + count) % count]
        AppNavigation.shared.show(next)
    }

    private func showAbout() {
        showAboutPanel()
    }
}
