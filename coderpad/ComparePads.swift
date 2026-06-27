//
//  ComparePads.swift
//  coderpad
//
//  A side-by-side pad comparison workspace (#594): a single window that hosts two or
//  more live pad browsers in resizable columns, so an interviewer can calibrate
//  candidates' solutions to the same question against each other. macOS-only - it leans
//  on `HSplitView` and a dedicated window; on iPad the same effect is reached with
//  Stage Manager / Split View over the existing per-pad windows.
//
//  The set of compared pads lives in a shared model rather than the window's scene
//  value, so the Pad menu's "Compare Pads…" can keep *adding* the focused pad to an
//  already-open workspace instead of spawning duplicates.
//

#if os(macOS)
    import SwiftUI

    /// One pad in the comparison workspace.
    struct ComparePad: Identifiable, Hashable {
        /// The pad's slug id.
        let id: String
        let title: String
        let url: URL

        /// Builds a comparison entry from a pad, or `nil` when the pad has no web URL
        /// to load (so it can't be shown in a browser column).
        init?(pad: Pad) {
            guard let url = pad.webURL else { return nil }

            id = pad.id
            title = pad.title.isEmpty ? pad.id : pad.title
            self.url = url
        }
    }

    @MainActor
    @Observable
    final class ComparePadsModel {
        static let shared = ComparePadsModel()
        private init() {}

        /// The pads shown side by side, in column order.
        private(set) var pads: [ComparePad] = []

        /// Adds a pad to the workspace, ignoring a pad that's already shown so the same
        /// pad can't occupy two columns.
        func add(_ pad: ComparePad) {
            guard !pads.contains(where: { $0.id == pad.id }) else { return }

            pads.append(pad)
        }

        func remove(_ id: String) {
            pads.removeAll { $0.id == id }
        }
    }

    struct ComparePadsView: View {
        @State private var model = ComparePadsModel.shared
        @State private var store = AccountsStore.shared
        @State private var padsCache = PadsCacheStore.shared

        var body: some View {
            Group {
                if model.pads.isEmpty {
                    emptyState
                } else {
                    HSplitView {
                        ForEach(model.pads) { pad in
                            column(pad)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addPadMenu
                }
            }
            .navigationTitle("Compare Pads")
            .frame(minWidth: 720, minHeight: 480)
        }

        /// One comparison column: a header naming the pad with a remove control, over
        /// its live in-app browser.
        private func column(_ pad: ComparePad) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(pad.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        model.remove(pad.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from comparison")
                    .accessibilityLabel("Remove \(pad.title) from comparison")
                }
                .padding(8)
                Divider()
                PadBrowserView(url: pad.url)
            }
            .frame(minWidth: 320)
        }

        /// The current account's pads not already shown, newest first, that can load in
        /// a browser column.
        private var availablePads: [Pad] {
            guard let id = store.currentAccountID else { return [] }

            let shown = Set(model.pads.map(\.id))
            return padsCache.get(id)
                .filter { !shown.contains($0.id) && $0.webURL != nil }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }

        private var addPadMenu: some View {
            Menu {
                let pads = availablePads
                if pads.isEmpty {
                    Text("No more pads to add")
                } else {
                    ForEach(pads.prefix(50)) { pad in
                        Button(pad.title.isEmpty ? pad.id : pad.title) {
                            if let entry = ComparePad(pad: pad) { model.add(entry) }
                        }
                    }
                }
            } label: {
                Label("Add Pad", systemImage: "plus")
            }
            .help("Add a pad to the comparison")
        }

        private var emptyState: some View {
            ContentUnavailableView {
                Label("Compare Pads", systemImage: "rectangle.split.2x1")
            } description: {
                Text("Add two or more pads to view them side by side.")
            } actions: {
                addPadMenu
            }
        }
    }
#endif
