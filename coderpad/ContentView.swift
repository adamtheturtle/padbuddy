//
//  ContentView.swift
//  coderpad
//

import SwiftUI

struct ContentView: View {
    @State private var store = APIKeyStore.shared
    @State private var pads: [Pad] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selection: Pad?
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            Group {
                if store.apiKey.isEmpty {
                    missingKeyView
                } else if isLoading && pads.isEmpty {
                    ProgressView("Loading pads…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn't load pads",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if pads.isEmpty {
                    ContentUnavailableView("No pads", systemImage: "tray")
                } else {
                    List(pads, selection: $selection) { pad in
                        NavigationLink(value: pad) {
                            PadRow(pad: pad)
                        }
                    }
                }
            }
            .navigationTitle("Pads")
            .navigationSplitViewColumnWidth(min: 240, ideal: 320)
            .toolbar {
                ToolbarItem {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem {
                    Button(action: { Task { await reload() } }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || store.apiKey.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
        } detail: {
            if let selection {
                PadDetailView(pad: selection)
            } else {
                Text(store.apiKey.isEmpty ? "Set your API key in Settings" : "Select a pad")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: store.apiKey) {
            guard !store.apiKey.isEmpty else { return }
            await reload()
        }
    }

    private var missingKeyView: some View {
        ContentUnavailableView {
            Label("No API key", systemImage: "key")
        } description: {
            Text("Open Settings and paste your CoderPad API key.")
        } actions: {
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = CoderPadClient(apiKey: store.apiKey)
            pads = try await client.listPads()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PadRow: View {
    let pad: Pad

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pad.title).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Text(pad.state.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(stateColor)
                Text(pad.ownerEmail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let updatedAt = pad.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var stateColor: Color {
        switch pad.state {
        case "started": return .green
        case "ended": return .gray
        default: return .blue
        }
    }
}

private struct PadDetailView: View {
    let pad: Pad

    var body: some View {
        Form {
            Section("Pad") {
                LabeledContent("ID", value: pad.id)
                LabeledContent("Title", value: pad.title)
                LabeledContent("State", value: pad.state)
                LabeledContent("Owner", value: pad.ownerEmail)
                if let language = pad.language {
                    LabeledContent("Language", value: language)
                }
            }
            Section("Participants") {
                if pad.participants.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(pad.participants, id: \.self) { name in
                        Text(name)
                    }
                }
            }
            Section("Timing") {
                if let createdAt = pad.createdAt {
                    LabeledContent("Created", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let updatedAt = pad.updatedAt {
                    LabeledContent("Updated", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let endedAt = pad.endedAt {
                    LabeledContent("Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                Link("Open in CoderPad", destination: URL(string: pad.url) ?? URL(string: "https://coderpad.io")!)
            }
        }
        .navigationTitle(pad.title)
    }
}

#Preview {
    ContentView()
}
