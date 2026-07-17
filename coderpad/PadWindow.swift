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
    /// Which window value produced `fetched`, compared whole (account AND id): pad
    /// slugs can collide across custom servers, so an id-only staleness check let a
    /// reused window keep showing another account's pad (#732).
    @State private var fetchedFor: PadWindowID?
    @State private var loadFailed = false
    @State private var refreshError: String?
    @State private var fallbackAccountID: UUID?

    /// The owning account: the one named in the value, or the current account captured
    /// when a legacy/restored value omits it. The fallback is intentionally sticky so
    /// switching accounts elsewhere cannot retarget this standalone window.
    private var account: Account? {
        guard let value else { return nil }

        let id = value.account ?? fallbackAccountID ?? accounts.currentAccountID
        return id.flatMap { id in accounts.accounts.first { $0.id == id } }
    }

    /// The pad from the warm cache, if the owning account has it loaded.
    private var cachedPad: Pad? {
        guard let value, let account else { return nil }

        return cache.cached(account.id).first { $0.id == value.id }
    }

    var body: some View {
        Group {
            if let account, let pad = fetched ?? cachedPad {
                VStack(spacing: 0) {
                    if let refreshError {
                        StaleRefreshBanner(message: refreshError) {
                            Task { await refresh() }
                        }
                    }
                    PadDetailView(client: account.makeClient(), pad: pad)
                        .advertisesPadActivity(url: pad.webURL, title: pad.title)
                }
                .navigationTitle(pad.title.isEmpty ? pad.id : pad.title)
            } else if value == nil || loadFailed {
                // The system can restore this window without a value, or the fetch
                // can fail (e.g. the pad was deleted); show a placeholder rather
                // than a blank window.
                ContentUnavailableView {
                    Label("Pad Unavailable", systemImage: "doc.questionmark")
                } description: {
                    Text("This pad couldn’t be loaded.")
                } actions: {
                    if value != nil {
                        Button("Retry") {
                            Task { await refresh() }
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: value) { await load() }
        .onReloadRequest { await refresh() }
    }

    /// Fetch the pad after first paint so restored windows don't treat persisted
    /// list snapshots as authoritative.
    private func load() async {
        captureFallbackAccountIfNeeded()
        // If the window was reused for a different pad or a different account (pad
        // slugs can collide across custom servers), drop the previous fetch so its
        // stale result can't satisfy the `fetched == nil` guard (and can't render
        // via `fetched ?? cachedPad`) (#732).
        if fetched != nil, fetchedFor != value {
            fetched = nil
            loadFailed = false
            refreshError = nil
        }
        await refresh()
    }

    private func captureFallbackAccountIfNeeded() {
        guard value?.account == nil, fallbackAccountID == nil else { return }

        fallbackAccountID = accounts.currentAccountID
    }

    private func refresh() async {
        guard let value, let account else { return }

        do {
            let pad = try await account.makeClient().getPad(id: value.id)
            fetched = pad
            fetchedFor = value
            loadFailed = false
            refreshError = nil
            AppRouter.padUpdated(pad)
        } catch is CancellationError {
            return
        } catch {
            if cachedPad == nil, fetched == nil {
                loadFailed = true
            } else {
                refreshError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
