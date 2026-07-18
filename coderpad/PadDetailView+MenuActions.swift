//
//  PadDetailView+MenuActions.swift
//  coderpad
//
//  The Pad-menu command handlers and the pad/event/environment loading for
//  PadDetailView, split out of PadDetailView.swift to keep each file under the
//  length limit. These are module-internal (not private) so the view's `body`,
//  which stays in the main file, can drive them across the file boundary.
//

import SwiftUI

private struct PadHistoryRequest {
    let url: String
    let title: String
    let language: String?
}

extension PadDetailView {
    /// Honors a "Watch Playback" request from the Pad menu, opening the session
    /// playback exactly as the toolbar's Watch button does.
    func consumePendingWatch() {
        guard nav.watchPlaybackPadID == pad.id else { return }

        nav.watchPlaybackPadID = nil
        guard let playbackURL = pad.playbackURL else { return }

        BrowserSettings.openExternally(playbackURL)
    }

    /// Honors a "Save All Code" request from the Pad menu by running the same save
    /// panel as the in-pane button (which knows which environments have loaded).
    func consumePendingSaveCode() {
        guard nav.saveCodePadID == pad.id else { return }

        nav.saveCodePadID = nil
        saveCodeLocally()
    }

    /// Honors a "Favorite" request from the Pad menu by toggling the same
    /// per-account favorite state as the in-pane toolbar star.
    func consumePendingFavoriteToggle() {
        guard nav.toggleFavoritePadID == pad.id else { return }

        nav.toggleFavoritePadID = nil
        toggleFavorite()
    }

    /// Consumes an "Edit Pad" request routed via `AppNavigation` from the Pad menu,
    /// opening the title editor.
    func consumePendingEdit() {
        guard nav.editPadID == pad.id else { return }

        nav.editPadID = nil
        titleEditRequest += 1
    }

    /// Honors an "End Interview" request from the Pad menu by showing the same
    /// confirmation as the in-pane action — never ending the session without it.
    func consumePendingEnd() {
        guard nav.endPadID == pad.id else { return }

        nav.endPadID = nil
        showEndConfirm = true
    }

    /// Honors a "Delete Pad" request from the Pad menu by showing the same delete
    /// confirmation as the in-pane Delete action.
    func consumePendingDelete() {
        guard nav.deletePadID == pad.id else { return }

        nav.deletePadID = nil
        showDeleteConfirm = true
    }

    func endInterview() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.endPad(id: pad.id)
            do {
                // Refresh so the authoritative ended state/timestamp propagate to the list and detail.
                let updated = try await client.getPad(id: pad.id)
                AppRouter.padUpdated(updated)
            } catch {
                AppRouter.padUpdated(optimisticEndedPad())
                mutateError = """
                The interview was ended, but the latest pad details couldn't be refreshed. \
                Reload to confirm the final timestamp.
                """
            }
        } catch {
            mutateError = error.localizedDescription
        }
    }

    private func optimisticEndedPad(now: Date = Date()) -> Pad {
        Pad(
            id: pad.id, title: pad.title, state: "ended", ownerEmail: pad.ownerEmail,
            language: pad.language, participants: pad.participants, url: pad.url,
            playback: pad.playback, events: pad.events, notes: pad.notes,
            drawing: pad.drawing, contents: pad.contents, history: pad.history,
            createdAt: pad.createdAt, updatedAt: now, endedAt: now,
            type: pad.type, executionEnabled: pad.executionEnabled, isPrivate: pad.isPrivate,
            activeEnvironmentID: pad.activeEnvironmentID, padEnvironmentIDs: pad.padEnvironmentIDs,
            questionIDs: pad.questionIDs, team: pad.team
        )
    }

    func deletePad() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.deletePad(id: pad.id)
            AppRouter.padDeleted(id: pad.id)
        } catch {
            mutateError = error.localizedDescription
        }
    }

    /// Grace period during which a confirmed deletion can still be undone.
    private static let deletionGracePeriod: Duration = .seconds(5)

    /// Begins a delayed deletion: an undo banner appears for the grace period, and
    /// the API delete only fires if it isn't cancelled.
    func startDeletion() {
        guard deletionTask == nil else { return }

        deletionTask = Task {
            try? await Task.sleep(for: Self.deletionGracePeriod)
            if Task.isCancelled { return }
            await deletePad()
            deletionTask = nil
        }
    }

    func cancelDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
    }

    @ViewBuilder
    var undoDeletionBanner: some View {
        if deletionTask != nil {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text("Deleting “\(pad.title.isEmpty ? "this pad" : pad.title)”…")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { cancelDeletion() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.subtleStroke, lineWidth: 1))
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    func load() async {
        // One request at a time: over cached content `isLoading` stays false, so
        // without this guard repeated Retry clicks each launched another events
        // fetch plus every environment request, racing their completions (#787).
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // Only show the blocking spinner when there's nothing to show yet. When the
        // pad was seeded from the session cache (or a prior load), refresh silently
        // over the existing content instead of flashing the spinner on top (#323).
        let hasContent = !events.isEmpty || !environments.isEmpty
        if !hasContent { isLoading = true }

        async let events = client.padEvents(padID: pad.id)
        async let envs = loadEnvironments()
        // Assign environments first — `loadEnvironments` can't throw — so a
        // failing events fetch doesn't leave environments (and the Save All Code
        // availability that depends on them) stale. Both still run concurrently.
        let loadedEnvironments = await envs
        environments = loadedEnvironments

        do {
            // The API returns events newest-first; display them oldest-first so the
            // log reads top-to-bottom in chronological order (and so the grouping
            // logic, which collapses consecutive same-kind events into an
            // earliest–latest range, stays correct).
            let loadedEvents = try await events.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            self.events = loadedEvents
            // Cleared on success rather than up front, so the failure card (and its
            // now-disabled Retry) stays visible while the retry is in flight instead
            // of flashing away and back if the retry also fails (#787).
            loadError = nil
            // Warm the session cache so a later return to this pad is instant.
            PadDetailCacheStore.shared.set(pad.id, client: client, events: loadedEvents,
                                           environments: loadedEnvironments)
        } catch {
            loadError = error
        }
        isLoading = false

        await loadHistories(for: loadedEnvironments)
        PadDetailCacheStore.shared.set(pad.id, client: client, events: self.events, environments: loadedEnvironments,
                                       histories: histories)
    }

    private func loadHistories(for environments: [PadEnvironment]) async {
        let requests = historyRequests(for: environments)
        guard !requests.isEmpty else {
            histories = []
            return
        }

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let loaded = await withTaskGroup(of: PadFileHistory?.self) { group in
            for request in requests {
                group.addTask {
                    guard let history = try? await client.padHistory(historyURL: request.url) else {
                        return nil
                    }
                    guard !history.isEmpty else { return nil }

                    return PadFileHistory(
                        id: request.url,
                        title: request.title,
                        language: request.language,
                        history: history
                    )
                }
            }

            var collected: [PadFileHistory] = []
            for await history in group {
                if let history {
                    collected.append(history)
                }
            }
            return collected
        }
        let order = Dictionary(uniqueKeysWithValues: requests.enumerated().map { ($1.url, $0) })
        histories = loaded.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    private func historyRequests(for environments: [PadEnvironment]) -> [PadHistoryRequest] {
        var requests: [PadHistoryRequest] = []
        var seen = Set<String>()

        func append(url: String?, title: String, language: String?) {
            // History URLs are API data; fetch only HTTPS URLs on trusted origins so a
            // malicious record can't make the app request localhost or the LAN (#856).
            guard let url, !url.isEmpty,
                  PadHistoryURLValidation.isAllowed(url, accountBaseURL: client.baseURL),
                  seen.insert(url).inserted else { return }

            requests.append(PadHistoryRequest(url: url, title: title, language: language))
        }

        for environment in environments {
            let displayFiles = displayFiles(for: environment)
            for (index, file) in environment.fileContents.enumerated() {
                let displayFile = displayFiles.indices.contains(index) ? displayFiles[index] : nil
                let title = displayFile?.path
                    ?? file.path
                    ?? String(localized: "File \(index + 1)")
                append(url: file.history, title: title, language: displayFile?.language)
            }
        }

        return requests
    }

    private func loadEnvironments() async -> [PadEnvironment] {
        // `pad_environment_ids` comes straight off the wire, so collapse duplicates
        // first: a repeated id both fetched (and displayed) the same environment
        // twice and trapped the ordering map's `uniqueKeysWithValues` below (#786).
        var seenIDs = Set<Int>()
        let ids = pad.padEnvironmentIDs.filter { seenIDs.insert($0).inserted }

        // Fan the per-id fetches out concurrently rather than awaiting each in turn,
        // so an N-environment pad pays ~1×RTT instead of N×RTT before its code
        // preview appears (#371). Order is restored by id afterward, since task
        // groups yield results as they finish.
        let environments = await withTaskGroup(of: PadEnvironment?.self) { group in
            for id in ids {
                group.addTask { try? await client.padEnvironment(id: id) }
            }
            var collected: [PadEnvironment] = []
            for await env in group {
                if let env { collected.append(env) }
            }
            return collected
        }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return environments.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}
