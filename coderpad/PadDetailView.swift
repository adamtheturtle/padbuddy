//
//  PadDetailView.swift
//  coderpad
//

import AppKit
import SwiftUI

struct PadDetailView: View {
    let client: CoderPadClient
    let pad: Pad
    @State var events: [PadEvent] = []
    @State var environments: [PadEnvironment] = []
    @State var loadError: Error?
    @State var isLoading = false
    @State private var showEdit = false
    @State var browserURL: URL?
    @State private var showEndConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isMutating = false
    @State var mutateError: String?
    @State private var nav = AppNavigation.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.orgDirectory) var directory
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if let url = browserURL {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button {
                            browserURL = nil
                        } label: {
                            Label("Back to Details", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button {
                            openWindow(id: "pad-browser", value: url)
                        } label: {
                            Image(systemName: "macwindow.badge.plus")
                        }
                        .help("Open in separate window")
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open in separate window")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .floatingGlass(in: Rectangle(), fallback: .thinMaterial)
                    Divider()
                    PadBrowserView(url: url)
                }
            } else {
                detailScroll
            }
        }
        .navigationTitle(pad.title.isEmpty ? pad.id : pad.title)
        // Detail-column actions live in the unified window toolbar rather than in
        // the content header: there they float on the system Liquid Glass layer
        // automatically, and the header stays free for identity and metadata. A
        // leading spacer separates them from the Pads list's own toolbar items
        // (Reload, New Pad). The lifecycle/destructive actions (Save Code, End
        // Interview, Delete Pad) sit in their own trailing group behind a second
        // spacer; End Interview and Delete Pad each still require a confirmation
        // dialog, so surfacing them directly can't trigger an irreversible action
        // from a stray click.
        .toolbar(id: "pad.detail.toolbar") {
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "editPad", placement: .primaryAction) {
                Button { showEdit = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit pad properties")
            }
            if let url = pad.webURL {
                ToolbarItem(id: "sharePad", placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share pad")
                    .accessibilityLabel("Share pad")
                }
                ToolbarItem(id: "openPad", placement: .primaryAction) {
                    Button {
                        if BrowserSettings.openLinksIn == .external {
                            BrowserSettings.openExternally(url)
                        } else {
                            browserURL = url
                        }
                    } label: {
                        // Short title ("Open", not "Open Pad") so it doesn't truncate
                        // to "O…" when the detail column is narrow and the toolbar is
                        // crowded; the accessibility label stays descriptive.
                        Label("Open", systemImage: "doc.text.image")
                    }
                    .help("Open the pad")
                    .accessibilityLabel("Open pad")
                }
            }
            if let playbackURL = pad.playbackURL {
                ToolbarItem(id: "watchPlayback", placement: .primaryAction) {
                    Button {
                        if BrowserSettings.openLinksIn == .external {
                            BrowserSettings.openExternally(playbackURL)
                        } else {
                            browserURL = playbackURL
                        }
                    } label: {
                        Label("Watch", systemImage: "play.rectangle")
                    }
                    .help("Watch the session playback")
                    .accessibilityLabel("Watch playback")
                }
            }
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "saveCode", placement: .primaryAction) {
                Button {
                    saveCodeLocally()
                } label: {
                    Label("Save Code…", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasSavableCode)
                .help("Save the pad's code to a file or folder on this Mac")
            }
            ToolbarItem(id: "endInterview", placement: .primaryAction) {
                Button {
                    showEndConfirm = true
                } label: {
                    Label("End Interview", systemImage: "flag.checkered")
                }
                .disabled(isEnded || isMutating)
                .help("End the interview for all participants")
            }
            ToolbarItem(id: "deletePad", placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Pad", systemImage: "trash")
                }
                .disabled(isMutating)
                .help("Delete this pad")
            }
        }
        .task(id: pad.id) { await load() }
        .sheet(isPresented: $showEdit) {
            EditPadSheet(
                client: client,
                original: pad,
                onSaved: { updated in
                    NotificationCenter.default.post(name: .padUpdated, object: updated)
                    showEdit = false
                },
                onCancel: { showEdit = false }
            )
        }
        .confirmationDialog("End this interview?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Interview", role: .destructive) { Task { await endInterview() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ending the interview stops the live session for all participants.")
        }
        .confirmationDialog("Delete this pad?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Pad", role: .destructive) { Task { await deletePad() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting the pad is permanent and cannot be undone.")
        }
        .alert("Action failed",
               isPresented: .init(get: { mutateError != nil },
                                  set: { if !$0 { mutateError = nil } })) {
            Button("OK", role: .cancel) { mutateError = nil }
        } message: {
            Text(mutateError ?? "")
        }
        .onAppear {
            consumePendingEdit()
            consumePendingEnd()
            consumePendingDelete()
            consumePendingWatch()
            consumePendingSaveCode()
        }
        .onChange(of: nav.editPadID) { _, _ in consumePendingEdit() }
        .onChange(of: nav.endPadID) { _, _ in consumePendingEnd() }
        .onChange(of: nav.deletePadID) { _, _ in consumePendingDelete() }
        .onChange(of: nav.watchPlaybackPadID) { _, _ in consumePendingWatch() }
        .onChange(of: nav.saveCodePadID) { _, _ in consumePendingSaveCode() }
    }

    /// Honors a "Watch Playback" request from the Pad menu, opening the session
    /// playback exactly as the toolbar's Watch button does — in-app or external
    /// per the browser preference.
    private func consumePendingWatch() {
        guard nav.watchPlaybackPadID == pad.id else { return }
        nav.watchPlaybackPadID = nil
        guard let playbackURL = pad.playbackURL else { return }
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(playbackURL)
        } else {
            browserURL = playbackURL
        }
    }

    /// Honors a "Save Code" request from the Pad menu by running the same save
    /// panel as the in-pane button (which knows which environments have loaded).
    private func consumePendingSaveCode() {
        guard nav.saveCodePadID == pad.id else { return }
        nav.saveCodePadID = nil
        saveCodeLocally()
    }

    /// Honors an "Edit Pad" request routed via `AppNavigation` from the Pad menu
    /// command by presenting the same edit sheet as the in-pane Edit button.
    private func consumePendingEdit() {
        guard nav.editPadID == pad.id else { return }
        nav.editPadID = nil
        showEdit = true
    }

    /// Honors an "End Interview" request from the Pad menu by showing the same
    /// confirmation as the in-pane action — never ending the session without it.
    private func consumePendingEnd() {
        guard nav.endPadID == pad.id else { return }
        nav.endPadID = nil
        showEndConfirm = true
    }

    /// Honors a "Delete Pad" request from the Pad menu by showing the same delete
    /// confirmation as the in-pane Delete action.
    private func consumePendingDelete() {
        guard nav.deletePadID == pad.id else { return }
        nav.deletePadID = nil
        showDeleteConfirm = true
    }

    private var isEnded: Bool {
        pad.isEnded
    }

    private func endInterview() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.endPad(id: pad.id)
            // Refresh so the ended state/timestamp propagate to the list and detail.
            if let updated = try? await client.getPad(id: pad.id) {
                NotificationCenter.default.post(name: .padUpdated, object: updated)
            }
        } catch {
            mutateError = error.localizedDescription
        }
    }

    private func deletePad() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.deletePad(id: pad.id)
            NotificationCenter.default.post(name: .padDeleted, object: pad.id)
        } catch {
            mutateError = error.localizedDescription
        }
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let events = client.padEvents(padID: pad.id)
            async let envs = loadEnvironments()
            // The API returns events newest-first; display them oldest-first so the
            // log reads top-to-bottom in chronological order (and so the grouping
            // logic, which collapses consecutive same-kind events into an
            // earliest–latest range, stays correct).
            self.events = try await events.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            environments = await envs
        } catch {
            loadError = error
        }
    }

    private func loadEnvironments() async -> [PadEnvironment] {
        var result: [PadEnvironment] = []
        for id in pad.padEnvironmentIDs {
            if let env = try? await client.padEnvironment(id: id) {
                result.append(env)
            }
        }
        return result
    }
}
