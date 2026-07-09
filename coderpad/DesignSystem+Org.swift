//
//  DesignSystem+Org.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#endif
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
            .linkButtonStyle()
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
    /// The stable default for `EnvironmentValues.orgDirectory`, so the `@Entry` value
    /// isn't reallocated on every access (the real directory is injected at the window
    /// root in `ContentView`). MainActor-isolated like the type, matching the env access.
    static let placeholder = OrgDirectory()

    private(set) var nameByEmail: [String: String] = [:]
    /// The organization's default coding language, used to pre-select the picker
    /// in the New Pad / New Question sheets. `nil` until the org loads or when the
    /// org reports no default.
    private(set) var defaultLanguage: String?
    private var loadedAccountID: UUID?
    private var inFlight: UUID?

    /// Seed the name map from disk so pad/question rows resolve owner names on the
    /// very first render after a cold launch, instead of flashing the raw email
    /// until the organization fetch returns. Mirrors the pads/questions caches'
    /// stale-while-revalidate: the persisted snapshot warms the UI, then the async
    /// `load`/`loadMerged` refreshes it from the network.
    ///
    /// `seedFromDisk` defaults to true for production. Tests that assert on a
    /// directory's load behavior pass `false` so a persisted `DirectoryCache` left on
    /// disk by a real app run (the cache dir is shared, not sandboxed per test) can't
    /// pre-populate the map and make a "fresh" directory look non-empty.
    init(seedFromDisk: Bool = true) {
        nameByEmail = seedFromDisk ? Self.cachedSeed() : [:]
    }

    /// The persisted name map for whichever list appears first: the union of every
    /// mergeable account in the combined view, or just the current account
    /// otherwise. Read synchronously so the first row render already has names.
    private static func cachedSeed() -> [String: String] {
        let store = AccountsStore.shared
        if store.isMergedView {
            var merged: [String: String] = [:]
            for account in store.mergeableAccounts {
                merged.merge(DirectoryCache.load(account: account.id)) { first, _ in first }
            }
            return merged
        }
        if let id = store.currentAccount?.id {
            return DirectoryCache.load(account: id)
        }
        return [:]
    }

    func load(for account: Account) async {
        guard loadedAccountID != account.id, inFlight != account.id else { return }

        inFlight = account.id
        defer { inFlight = nil }
        let client = account.makeClient()
        if let org = try? await OrganizationCacheStore.shared.organization(via: client) {
            var map: [String: String] = [:]
            for user in org.users {
                if let name = user.name, !name.isEmpty {
                    map[user.email] = name
                }
            }
            nameByEmail = map
            defaultLanguage = org.organizationDefaultLanguage.flatMap { $0.isEmpty ? nil : $0 }
            loadedAccountID = account.id
            // Persist for the next cold launch. Skip an empty map so a transient
            // fetch hiccup can't wipe a previously good snapshot.
            if !map.isEmpty { DirectoryCache.save(map, account: account.id) }
        }
    }

    /// Load and union the member directories of several accounts at once, for the
    /// combined "All Accounts" view where owner emails span every org. Fetches each
    /// account's organization concurrently and merges the name maps so a pad from
    /// any account can still resolve its owner's display name. `loadedAccountID` is
    /// cleared so a later single-account `load` refreshes rather than no-ops.
    func loadMerged(for accounts: [Account]) async {
        let realAccounts = accounts.filter { !$0.apiKey.isEmpty }
        guard !realAccounts.isEmpty else { return }

        let maps = await withTaskGroup(of: (UUID, [String: String]).self) { group -> [(UUID, [String: String])] in
            for account in realAccounts {
                let client = account.makeClient()
                let id = account.id
                group.addTask {
                    guard let org = try? await OrganizationCacheStore.shared.organization(via: client) else {
                        return (id, [:])
                    }

                    var map: [String: String] = [:]
                    for user in org.users where !(user.name ?? "").isEmpty {
                        map[user.email] = user.name
                    }
                    return (id, map)
                }
            }
            var collected: [(UUID, [String: String])] = []
            for await pair in group {
                collected.append(pair)
            }
            return collected
        }
        var merged: [String: String] = [:]
        for (account, map) in maps {
            merged.merge(map) { first, _ in first }
            // Persist each account's own map (not the union) so a later single-account
            // launch seeds from just that account. Skip empties to preserve a good
            // snapshot through a transient fetch hiccup.
            if !map.isEmpty { DirectoryCache.save(map, account: account) }
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

/// Disk backing for `OrgDirectory`'s email -> name map, one JSON file per account
/// under Application Support (via the shared `CacheDisk`). Lets owner names resolve
/// on the first render after a cold launch, the same stale-while-revalidate trick
/// the pads and questions lists already use.
private enum DirectoryCache {
    nonisolated static func load(account: UUID) -> [String: String] {
        CacheDisk.load([String: String].self, kind: "directory", account: account) ?? [:]
    }

    nonisolated static func save(_ map: [String: String], account: UUID) {
        CacheDisk.save(map, kind: "directory", account: account)
    }
}

extension EnvironmentValues {
    @Entry var orgDirectory = OrgDirectory.placeholder
    // `EnvironmentValues.isReadOnly` now lives in `BuddyDesignSystem` (#321), re-exported
    // via `DesignSystem.swift`, so the app's editing controls keep reading `\.isReadOnly`
    // unqualified. The `FocusedValues.isReadOnly` counterpart below is a separate key.
}

// APIErrorView lives in DesignSystem+APIErrorView.swift (split out for file length).
// Focused scene values and list copy/link helpers live in
// DesignSystem+FocusedActions.swift (split out for file length).
