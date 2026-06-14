//
//  DesignSystem+Org.swift
//  coderpad
//

import SwiftUI

// MARK: - EmailLink

struct EmailLink: View {
    let email: String

    var body: some View {
        if email.isEmpty {
            Text("(no email)").foregroundStyle(.secondary)
        } else if let url = URL(string: "mailto:\(email)") {
            Link(email, destination: url)
        } else {
            Text(email)
        }
    }
}

// MARK: - OwnerPadsLink

/// A pad or question owner's name, rendered as a link that jumps to that
/// person's pads — the same person-navigation the Organization list and
/// interviewer rows already use. Pairs with `EmailLink` at the call sites: the
/// name links to their pads while the email keeps its mailto, so the owner
/// identity gains navigation without losing the address it used to carry. When
/// the org directory doesn't know the name, the email itself becomes the label
/// and the mailto stays reachable from the context menu.
struct OwnerPadsLink: View {
    let email: String
    @Environment(\.orgDirectory) private var directory

    var body: some View {
        if email.isEmpty {
            Text("(no owner)").foregroundStyle(.secondary)
        } else {
            let name = directory.display(email)
            Button {
                AppNavigation.shared.showPads(PadsRequest(ownerEmail: email))
            } label: {
                Text(name)
            }
            .buttonStyle(.link)
            .help("Show pads from \(name)")
            .contextMenu {
                Button {
                    AppNavigation.shared.showPads(PadsRequest(ownerEmail: email))
                } label: {
                    Label("Show Pads from \(name)", systemImage: "person")
                }
                if let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) {
                        Label("Send Email", systemImage: "envelope")
                    }
                }
            }
            .accessibilityLabel("Owner \(name)")
            .accessibilityHint("Shows pads from \(name)")
        }
    }
}

// MARK: - Org directory (email -> name lookup)

@Observable
final class OrgDirectory {
    private(set) var nameByEmail: [String: String] = [:]
    /// The organization's default coding language, used to pre-select the picker
    /// in the New Pad / New Question sheets. `nil` until the org loads or when the
    /// org reports no default.
    private(set) var defaultLanguage: String?
    private var loadedAccountID: UUID?
    private var inFlight: UUID?

    func load(for account: Account) async {
        guard loadedAccountID != account.id, inFlight != account.id else { return }
        inFlight = account.id
        defer { inFlight = nil }
        let client = account.makeClient()
        if let org = try? await client.organization() {
            var map: [String: String] = [:]
            for user in org.users {
                if let name = user.name, !name.isEmpty {
                    map[user.email] = name
                }
            }
            nameByEmail = map
            defaultLanguage = org.organizationDefaultLanguage.flatMap { $0.isEmpty ? nil : $0 }
            loadedAccountID = account.id
        }
    }

    /// Load and union the member directories of several accounts at once, for the
    /// combined "All Accounts" view where owner emails span every org. Fetches each
    /// account's organization concurrently and merges the name maps so a pad from
    /// any account can still resolve its owner's display name. `loadedAccountID` is
    /// cleared so a later single-account `load` refreshes rather than no-ops.
    func loadMerged(for accounts: [Account]) async {
        let clients = accounts.filter { !$0.apiKey.isEmpty }.map { $0.makeClient() }
        guard !clients.isEmpty else { return }
        let maps = await withTaskGroup(of: [String: String].self) { group -> [[String: String]] in
            for client in clients {
                group.addTask {
                    guard let org = try? await client.organization() else { return [:] }
                    var map: [String: String] = [:]
                    for user in org.users where !(user.name ?? "").isEmpty {
                        map[user.email] = user.name
                    }
                    return map
                }
            }
            var collected: [[String: String]] = []
            for await map in group {
                collected.append(map)
            }
            return collected
        }
        var merged: [String: String] = [:]
        for map in maps {
            merged.merge(map) { first, _ in first }
        }
        nameByEmail = merged
        loadedAccountID = nil
    }

    func name(for email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nameByEmail[trimmed]
    }

    func display(_ email: String) -> String {
        name(for: email) ?? email
    }
}

extension EnvironmentValues {
    @Entry var orgDirectory = OrgDirectory()
}

// MARK: - Focused scene value for the selected pad

extension FocusedValues {
    /// The pad selected in the active window's list, published via
    /// `focusedSceneValue` so the Pad menu commands can act on it whenever the
    /// window is frontmost — independent of which subview holds keyboard focus.
    @Entry var focusedPad: Pad?
}

extension FocusedValues {
    /// The question selected in the active window's list, published via
    /// `focusedSceneValue` so the Question menu commands can act on it whenever the
    /// window is frontmost — the Questions-pane counterpart to `focusedPad`.
    @Entry var focusedQuestion: Question?
}

extension FocusedValues {
    /// Whether the selected question is a favorite of the current account,
    /// published by `QuestionDetailView` so the Question menu's Favorite command
    /// can show the matching "Add to"/"Remove from Favorites" title.
    @Entry var focusedQuestionIsFavorite: Bool?
}

extension FocusedValues {
    /// The selected question's web URL, published by `QuestionDetailView` so the
    /// Question menu's Share/Copy URL commands can act on it. Built from the
    /// account's server URL there (the question model has no URL of its own), so
    /// the menu honors a custom CoderPad domain — the Pad menu's counterpart reads
    /// `focusedPad.webURL` directly because pads carry an absolute API URL.
    @Entry var focusedQuestionURL: URL?
}

/// Action published by whichever pane currently owns a search field, so the
/// global ⌘F command can focus it. Panes set this via `focusedSceneValue` while
/// visible; the command reads it both to perform the find and to know whether
/// Find applies in the current context (it's disabled when no pane provides one).
///
/// `Equatable` on a stable per-pane `id` is load-bearing: the wrapped closure
/// can't be compared, so without it every body pass re-publishes a "new" value
/// for the same scene key. Because `NavigationSplitView` re-evaluates its panes
/// several times per layout pass, SwiftUI flags those redundant writes as
/// "FocusedValue update tried to update multiple times per frame." Comparing by
/// `id` lets SwiftUI dedupe the identical re-assignments instead.
struct FindAction: Equatable {
    /// Identifies the owning pane (e.g. "pads"), so re-publishes from the same
    /// pane compare equal while a genuine pane switch compares unequal.
    let id: String
    let perform: () -> Void

    static func == (lhs: FindAction, rhs: FindAction) -> Bool {
        lhs.id == rhs.id
    }
}

extension FocusedValues {
    @Entry var findAction: FindAction?
}

/// Action published by whichever detail pane can be printed, so the File menu's
/// ⌘P command can render it through the standard print panel. Like `FindAction`,
/// it's `Equatable` on a stable per-content `id` so re-publishes from the same
/// content dedupe instead of tripping SwiftUI's multiple-updates-per-frame
/// warning during `NavigationSplitView`'s repeated layout passes. The command
/// reads it both to perform the print and to disable itself when nothing focused
/// is printable.
struct PrintAction: Equatable {
    /// Identifies the printable content (e.g. "question-42"), so re-publishes for
    /// the same content compare equal while a genuine selection change differs.
    let id: String
    let perform: () -> Void

    static func == (lhs: PrintAction, rhs: PrintAction) -> Bool {
        lhs.id == rhs.id
    }
}

extension FocusedValues {
    @Entry var printAction: PrintAction?
}

// MARK: - APIErrorView

struct APIErrorView: View {
    let error: Error
    var onRetry: (() -> Void)?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let api = error as? CoderPadError, api.isUnauthorized {
            ContentUnavailableView {
                Label("Key not authorized", systemImage: "lock.shield")
            } description: {
                Text("Your API key was rejected (HTTP 401/403). Open Settings to switch accounts or paste a new key.")
            } actions: {
                VStack(spacing: 8) {
                    Button("Open Settings") {
                        let navigation = SettingsNavigation.shared
                        navigation.selectedTab = .accounts
                        navigation.accountToEdit = AccountsStore.shared.currentAccountID
                        openSettings()
                    }
                    .prominentGlassButtonStyle()
                    GetAPIKeyLink()
                    if let onRetry {
                        Button("Retry", action: onRetry)
                    }
                }
            }
        } else if let api = error as? CoderPadError, case .missingAPIKey = api {
            ContentUnavailableView {
                Label("No API key", systemImage: "key")
            } description: {
                Text("Add an account in Settings to start using the app.")
            } actions: {
                VStack(spacing: 8) {
                    Button("Open Settings") { openSettings() }
                        .prominentGlassButtonStyle()
                    GetAPIKeyLink()
                }
            }
        } else {
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                if let onRetry {
                    Button("Retry", action: onRetry)
                        .prominentGlassButtonStyle()
                }
            }
        }
    }
}
