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

struct PadHistoryRequest {
    let url: String
    let title: String
    let language: String?
}

struct PadDestructiveMutationGate: Equatable {
    enum Operation: Equatable {
        case ending
        case deleting
    }

    private(set) var operation: Operation?
    var isActive: Bool {
        operation != nil
    }

    mutating func begin(_ candidate: Operation) -> Bool {
        guard operation == nil else { return false }

        operation = candidate
        return true
    }

    mutating func finish(_ candidate: Operation) {
        guard operation == candidate else { return }

        operation = nil
    }
}

extension PadDetailView {
    /// Honors a "Watch Playback" request from the Pad menu, opening the session
    /// playback exactly as the toolbar's Watch button does.
    func consumePendingWatch() {
        guard let request = nav.watchPlaybackPadID, request.id == pad.id,
              request.account == nil || request.account == owningAccountID else { return }

        nav.watchPlaybackPadID = nil
        guard let playbackURL = pad.playbackURL else { return }

        BrowserSettings.openExternally(playbackURL)
    }

    /// Honors a "Save All Code" request from the Pad menu by running the same save
    /// panel as the in-pane button (which knows which environments have loaded).
    func consumePendingSaveCode() {
        guard let request = nav.saveCodePadID, request.id == pad.id,
              request.account == nil || request.account == owningAccountID else { return }

        nav.saveCodePadID = nil
        saveCodeLocally()
    }

    /// Honors a "Favorite" request from the Pad menu by toggling the same
    /// per-account favorite state as the in-pane toolbar star.
    func consumePendingFavoriteToggle() {
        guard let request = nav.toggleFavoritePadID, request.id == pad.id,
              request.account == nil || request.account == owningAccountID else { return }

        nav.toggleFavoritePadID = nil
        toggleFavorite()
    }

    /// Consumes an "Edit Pad" request routed via `AppNavigation` from the Pad menu,
    /// opening the title editor.
    func consumePendingEdit() {
        guard let request = nav.editPadID, request.id == pad.id,
              request.account == nil || request.account == owningAccountID else { return }

        nav.editPadID = nil
        titleEditRequest += 1
    }

    /// Honors an "End Interview" request from the Pad menu by showing the same
    /// confirmation as the in-pane action — never ending the session without it.
    func consumePendingEnd() {
        guard let request = nav.endPadID, request.id == pad.id,
              request.account == nil || request.account == owningAccountID else { return }

        nav.endPadID = nil
        guard !destructiveMutation.isActive else { return }

        showEndConfirm = true
    }

    /// Honors a "Delete Pad" request from the Pad menu by showing the same delete
    /// confirmation as the in-pane Delete action.
    func consumePendingDelete() {
        guard let request = nav.deletePadID, request.id == pad.id,
              request.account == nil || request.account == owningAccountID else { return }

        nav.deletePadID = nil
        guard !destructiveMutation.isActive else { return }

        showDeleteConfirm = true
    }

    func endInterview() async {
        guard destructiveMutation.begin(.ending) else { return }

        let account = owningAccountID
        let claim = AppRouter.beginPadUpdate(id: pad.id, account: account, via: client)
        defer { destructiveMutation.finish(.ending) }
        do {
            try await client.endPad(id: pad.id)
            do {
                // Refresh so the authoritative ended state/timestamp propagate to the list and detail.
                let updated = try await client.getPad(id: pad.id)
                guard AppRouter.isCurrentPadUpdate(claim) else { return }

                AppRouter.padUpdated(updated, account: account)
            } catch {
                guard AppRouter.isCurrentPadUpdate(claim) else { return }

                AppRouter.padUpdated(optimisticEndedPad(), account: account)
                mutateError = """
                The interview was ended, but the latest pad details couldn't be refreshed. \
                Reload to confirm the final timestamp.
                """
            }
        } catch {
            guard AppRouter.isCurrentPadUpdate(claim) else { return }

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
        guard destructiveMutation.operation == .deleting else { return }

        defer { destructiveMutation.finish(.deleting) }
        do {
            try await client.deletePad(id: pad.id)
            AppRouter.padDeleted(id: pad.id, account: owningAccountID, via: client)
        } catch {
            mutateError = error.localizedDescription
        }
    }

    /// Grace period during which a confirmed deletion can still be undone.
    private static let deletionGracePeriod: Duration = .seconds(5)

    /// Begins a delayed deletion: an undo banner appears for the grace period, and
    /// the API delete only fires if it isn't cancelled.
    func startDeletion() {
        guard deletionTask == nil, destructiveMutation.begin(.deleting) else { return }

        // Captured now, checked after the wait: the view can be rebound to another
        // pad — or its account re-keyed — during the grace period, and deleting
        // `pad.id` then would destroy whatever same-slug resource the view had moved
        // on to (#2370).
        let targetID = pad.id
        let targetAccount = owningAccountID
        deletionTask = Task {
            try? await Task.sleep(for: Self.deletionGracePeriod)
            if Task.isCancelled { return }
            guard pad.id == targetID, owningAccountID == targetAccount else {
                deletionTask = nil
                destructiveMutation.finish(.deleting)
                return
            }

            // The grace period is over: drop the banner (and its Undo) BEFORE the
            // irreversible API request starts. An Undo pressed mid-request would
            // pretend to cancel a deletion the server may still complete (#1753);
            // mirrors the question detail's #725 fix.
            deletionTask = nil
            await deletePad()
        }
    }

    func cancelDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
        destructiveMutation.finish(.deleting)
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
        let identity = detailLoadIdentity
        guard let generation = beginLoad(identity) else { return }

        defer {
            publishIfCurrent(generation, identity: identity) {
                isRefreshing = false
                refreshingIdentity = nil
            }
        }

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
        let (loadedEnvironments, failedIDs) = await envs
        publishIfCurrent(generation, identity: identity) {
            environments = loadedEnvironments
            displayFilesByEnvironment = Self.normalizedDisplayFiles(for: loadedEnvironments)
            failedEnvironmentIDs = failedIDs
        }

        do {
            // The API returns events newest-first; display them oldest-first so the
            // log reads top-to-bottom in chronological order (and so the grouping
            // logic, which collapses consecutive same-kind events into an
            // earliest–latest range, stays correct).
            let loadedEvents = try await events.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            publishIfCurrent(generation, identity: identity) {
                self.events = loadedEvents
                loadError = nil
                if failedIDs.isEmpty {
                    PadDetailCacheStore.shared.set(pad.id, client: client, events: loadedEvents,
                                                   environments: loadedEnvironments)
                }
            }
        } catch is CancellationError {
            // Switching pads cancels this load. That isn't a failure to report — the
            // new pad's load owns the view now, and setting `loadError` would leave
            // its card showing an error the user never caused (#2372).
            publishIfCurrent(generation, identity: identity) { isLoading = false }
            return
        } catch {
            publishIfCurrent(generation, identity: identity) {
                loadError = error
                isLoading = false
            }
            return
        }
        publishIfCurrent(generation, identity: identity) { isLoading = false }

        await loadHistories(for: loadedEnvironments, generation: generation, identity: identity)
        // Only a fully consistent snapshot is cached: after a failed events fetch,
        // `self.events` still holds the previous load's events, and persisting them
        // alongside fresh environments would serve a mixed pad snapshot as
        // authoritative on re-entry (#1752).
        // `historyLoadFailures` joins the check: caching a history set that is
        // missing files would serve it as complete on re-entry, and nothing would
        // retry the ones that failed (#2376).
        publishIfCurrent(generation, identity: identity) {
            if failedIDs.isEmpty, loadError == nil, historyLoadFailures == 0 {
                PadDetailCacheStore.shared.set(pad.id, client: client, events: self.events,
                                               environments: loadedEnvironments, histories: histories)
            }
        }
    }

    func historyRequests(for environments: [PadEnvironment]) -> [PadHistoryRequest] {
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

    private func loadEnvironments() async -> (loaded: [PadEnvironment], failedIDs: [Int]) {
        // `pad_environment_ids` comes straight off the wire, so collapse duplicates
        // first: a repeated id both fetched (and displayed) the same environment
        // twice and trapped the ordering map's `uniqueKeysWithValues` below (#786).
        // Zero/negative ids from corrupt records are dropped too — they can only
        // produce pointless invalid requests (#1751).
        var seenIDs = Set<Int>()
        let ids = pad.padEnvironmentIDs.filter { $0 > 0 && seenIDs.insert($0).inserted }

        // Fan the per-id fetches out concurrently rather than awaiting each in turn,
        // so an N-environment pad pays ~1×RTT instead of N×RTT before its code
        // preview appears (#371). Order is restored by id afterward, since task
        // groups yield results as they finish. Every requested id is tracked, so a
        // failed fetch surfaces as an explicit incomplete-code warning instead of
        // silently rendering fewer files (#713).
        // Bounded fan-out, matching the history fetches (#1750): a pad with many
        // environments must not open one connection per environment at once, and
        // each response carries that environment's whole file set (#2373). A fresh
        // request starts as each one finishes, keeping at most `width` in flight.
        let results = await withTaskGroup(of: (id: Int, environment: PadEnvironment?).self) { group in
            let width = 4
            var iterator = ids.makeIterator()
            var started = 0
            while started < width, let id = iterator.next() {
                group.addTask { await (id, try? client.padEnvironment(id: id)) }
                started += 1
            }

            var collected: [(id: Int, environment: PadEnvironment?)] = []
            for await result in group {
                collected.append(result)
                if let id = iterator.next() {
                    group.addTask { await (id, try? client.padEnvironment(id: id)) }
                }
            }
            return collected
        }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let loaded = results.compactMap(\.environment).sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        let failed = results.filter { $0.environment == nil }.map(\.id)
            .sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
        return (loaded, failed)
    }
}
