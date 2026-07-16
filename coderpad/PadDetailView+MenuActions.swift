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
            // Refresh so the ended state/timestamp propagate to the list and detail.
            if let updated = try? await client.getPad(id: pad.id) {
                AppRouter.padUpdated(updated)
            }
        } catch {
            mutateError = error.localizedDescription
        }
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

    func load() async {
        // Only show the blocking spinner when there's nothing to show yet. When the
        // pad was seeded from the session cache (or a prior load), refresh silently
        // over the existing content instead of flashing the spinner on top (#323).
        let hasContent = !events.isEmpty || !environments.isEmpty
        if !hasContent { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            async let events = client.padEvents(padID: pad.id)
            async let envs = loadEnvironments()
            // Assign environments first — `loadEnvironments` can't throw — so a
            // failing events fetch doesn't leave environments (and the Save All Code
            // availability that depends on them) stale. Both still run concurrently.
            let loadedEnvironments = await envs
            environments = loadedEnvironments
            // The API returns events newest-first; display them oldest-first so the
            // log reads top-to-bottom in chronological order (and so the grouping
            // logic, which collapses consecutive same-kind events into an
            // earliest–latest range, stays correct).
            let loadedEvents = try await events.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            self.events = loadedEvents
            // Warm the session cache so a later return to this pad is instant.
            PadDetailCacheStore.shared.set(pad.id, client: client, events: loadedEvents,
                                           environments: loadedEnvironments)
        } catch {
            loadError = error
        }
    }

    private func loadEnvironments() async -> [PadEnvironment] {
        // Fan the per-id fetches out concurrently rather than awaiting each in turn,
        // so an N-environment pad pays ~1×RTT instead of N×RTT before its code
        // preview appears (#371). Order is restored by id afterward, since task
        // groups yield results as they finish.
        let environments = await withTaskGroup(of: PadEnvironment?.self) { group in
            for id in pad.padEnvironmentIDs {
                group.addTask { try? await client.padEnvironment(id: id) }
            }
            var collected: [PadEnvironment] = []
            for await env in group {
                if let env { collected.append(env) }
            }
            return collected
        }
        let order = Dictionary(uniqueKeysWithValues: pad.padEnvironmentIDs.enumerated().map { ($1, $0) })
        return environments.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}
