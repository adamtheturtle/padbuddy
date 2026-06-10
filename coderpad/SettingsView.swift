//
//  SettingsView.swift
//  coderpad
//

import SwiftUI

struct SettingsView: View {
    @State private var store = APIKeyStore.shared
    @State private var draft: String = ""
    @State private var revealed = false

    var body: some View {
        Form {
            Section {
                Group {
                    if revealed {
                        TextField("CoderPad API key", text: $draft)
                    } else {
                        SecureField("CoderPad API key", text: $draft)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Toggle("Show key", isOn: $revealed)
                HStack {
                    Button("Save") { store.apiKey = draft.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines) == store.apiKey)
                    Button("Clear", role: .destructive) {
                        draft = ""
                        store.apiKey = ""
                    }
                    .disabled(store.apiKey.isEmpty && draft.isEmpty)
                    Spacer()
                    if !store.apiKey.isEmpty {
                        Label("Saved in Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                    }
                }
            } header: {
                Text("API")
            } footer: {
                Text("Stored in the macOS Keychain under service \"\(Keychain.service)\".")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 240)
        .onAppear { draft = store.apiKey }
    }
}

#Preview { SettingsView() }
