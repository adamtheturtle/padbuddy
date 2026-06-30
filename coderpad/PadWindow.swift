//
//  PadWindow.swift
//  coderpad
//
//  Hosts a pad's detail in its own window, opened by double-clicking a pad row
//  (#354) — the pad counterpart to ``QuestionWindow`` (#292). The window carries
//  only an identifier so it can be restored across launches; the heavyweight
//  `Pad` is resolved from the cache (or fetched) on appear.
//

import SwiftUI

/// Identifies a pad opened in its own window. Pad ids are global slugs, but the
/// owning account still travels with the id so the right account's client (and
/// custom server URL) is used. `account` is `nil` in a single-account context,
/// where it resolves to the current account. Codable and Hashable so it can back
/// a `WindowGroup(for:)` and survive state restoration.
struct PadWindowID: Codable, Hashable {
    var account: UUID?
    var id: String
}

/// Resolves a ``PadWindowID`` to its account and pad and shows the same
/// `PadDetailView` the main window's detail column uses. The pad comes from the
/// cache when present (the common case, since the window is opened from a loaded
/// row); otherwise it's fetched once, so a window restored on a cold cache still
/// fills in rather than showing an empty shell.
struct PadWindow: View {
    let value: PadWindowID?
    @State private var accounts = AccountsStore.shared
    @State private var cache = PadsCacheStore.shared
    @State private var fetched: Pad?
    @State private var loadFailed = false

    /// The owning account: the one named in the value, or the current account when
    /// the value omits it (single-account context).
    private var account: Account? {
        guard let value else { return nil }

        if let id = value.account { return accounts.accounts.first { $0.id == id } }
        return accounts.currentAccount
    }

    /// The pad from the warm cache, if the owning account has it loaded.
    private var cachedPad: Pad? {
        guard let value, let account else { return nil }

        return cache.get(account.id).first { $0.id == value.id }
    }

    var body: some View {
        Group {
            if let account, let pad = cachedPad ?? fetched {
                let detail = PadDetailView(client: account.makeClient(), pad: pad)
                    .navigationTitle(pad.title.isEmpty ? pad.id : pad.title)
                // The pad's web URL backs the title-bar proxy icon (#609), so the title
                // can be cmd-dragged to grab a link and right-clicked for the path popover.
                if let url = pad.webURL {
                    detail.navigationDocument(url)
                } else {
                    detail
                }
            } else if value == nil || loadFailed {
                // The system can restore this window without a value, or the fetch
                // can fail (e.g. the pad was deleted); show a placeholder rather
                // than a blank window.
                ContentUnavailableView("Pad Unavailable", systemImage: "doc.questionmark",
                                       description: Text("This pad couldn’t be loaded."))
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: value) { await loadIfNeeded() }
    }

    /// Fetch the pad once when it isn't in the cache, so a restored window on a
    /// cold cache fills in. Cache hits skip the network entirely.
    private func loadIfNeeded() async {
        // If the window was reused for a different pad, drop the previous fetch so
        // its stale result can't satisfy the `fetched == nil` guard (and can't
        // render via `cachedPad ?? fetched`).
        if let fetched, fetched.id != value?.id {
            self.fetched = nil
            loadFailed = false
        }
        guard cachedPad == nil, fetched == nil, let value, let account else { return }

        do {
            fetched = try await account.makeClient().getPad(id: value.id)
        } catch {
            loadFailed = true
        }
    }
}
