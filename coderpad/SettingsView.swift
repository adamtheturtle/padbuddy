//
//  SettingsView.swift
//  coderpad
//

import SwiftUI

struct SettingsView: View {
    @State private var store = AccountsStore.shared
    @State private var editingAccount: Account?

    var body: some View {
        TabView {
            accountsTab
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            helpTab
                .tabItem { Label("How to get a key", systemImage: "questionmark.circle") }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 420)
        .sheet(item: $editingAccount) { account in
            AccountEditor(initial: account) { updated in
                if store.accounts.contains(where: { $0.id == updated.id }) {
                    store.update(updated)
                } else {
                    store.add(updated)
                }
                editingAccount = nil
            } onCancel: {
                editingAccount = nil
            }
        }
    }

    private var accountsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                Button {
                    editingAccount = Account(name: "", apiKey: "")
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }

            if store.accounts.isEmpty {
                ContentUnavailableView {
                    Label("No accounts", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Add an account with a CoderPad API key.")
                } actions: {
                    Button("Add Account") {
                        editingAccount = Account(name: "", apiKey: "")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.accounts) { account in
                        AccountRow(
                            account: account,
                            isCurrent: account.id == store.currentAccountID,
                            onMakeCurrent: { store.currentAccountID = account.id },
                            onEdit: { editingAccount = account },
                            onDelete: { store.remove(id: account.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var helpTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("How to get a CoderPad API key", systemImage: "key.fill")
                    .font(.title3.bold())

                Text("You'll need a paid CoderPad Interview seat and admin access to your organization. Personal-trial accounts may not have API access.")
                    .foregroundStyle(.secondary)

                Divider()

                stepsView

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Useful links").font(.headline)
                    Link(destination: URL(string: "https://app.coderpad.io/dashboard/settings/api")!) {
                        Label("Open your API settings on CoderPad", systemImage: "arrow.up.forward.app")
                    }
                    Link(destination: URL(string: "https://coderpad.io/resources/docs/coderpad-interview/api/")!) {
                        Label("CoderPad API documentation", systemImage: "book")
                    }
                }

                Divider()

                Text("Security").font(.headline)
                Text("Keys are stored in the macOS Keychain under service \"\(Keychain.service)\". You can manage them with Keychain Access.app or rotate them at any time on the CoderPad dashboard.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(number: 1, title: "Sign in to CoderPad", body: "Go to app.coderpad.io and sign in with an admin account.")
            step(number: 2, title: "Open Account → API", body: "Click your avatar in the top right, choose Account, then the API tab. (Or use the direct link above.)")
            step(number: 3, title: "Generate or copy a key", body: "Click Generate API Key (or copy an existing one). Keys are long random strings — treat them like passwords.")
            step(number: 4, title: "Paste it into a new account here", body: "Click Add Account, give it a label like \"Production\", paste the key, and click Validate & Save.")
        }
    }

    @ViewBuilder
    private func step(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(body).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let isCurrent: Bool
    let onMakeCurrent: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(label: account.name, diameter: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name.isEmpty ? "Untitled account" : account.name)
                        .font(.callout.weight(.medium))
                    if isCurrent {
                        Text("Current")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(mask(account.apiKey))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isCurrent {
                Button("Use") { onMakeCurrent() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button { onEdit() } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func mask(_ key: String) -> String {
        guard key.count > 6 else { return String(repeating: "•", count: max(key.count, 4)) }
        let tail = key.suffix(4)
        return String(repeating: "•", count: 8) + " " + tail
    }
}

enum ValidationState: Equatable {
    case idle
    case validating
    case valid(String)
    case invalid(String)
}

private struct AccountEditor: View {
    @State var draft: Account
    let initialName: String
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    @State private var reveal = false
    @State private var validation: ValidationState = .idle

    init(initial: Account, onSave: @escaping (Account) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: initial)
        self.initialName = initial.name
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(initialName.isEmpty ? "Add account" : "Edit account").font(.title3.bold())
            Form {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Production"))
                Group {
                    if reveal {
                        TextField("API key", text: $draft.apiKey, prompt: Text("paste key"))
                    } else {
                        SecureField("API key", text: $draft.apiKey, prompt: Text("paste key"))
                    }
                }
                Toggle("Show key", isOn: $reveal)
            }
            .formStyle(.grouped)

            validationBanner

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Validate") { Task { await validate() } }
                    .disabled(draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || validation == .validating)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 320)
        .onChange(of: draft.apiKey) { _, _ in validation = .idle }
    }

    @ViewBuilder
    private var validationBanner: some View {
        switch validation {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking key…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case .valid(let org):
            Label("Valid — \(org)", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green).font(.callout)
        case .invalid(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout)
        }
    }

    private func validate() async {
        validation = .validating
        do {
            let client = CoderPadClient(apiKey: draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            let org = try await client.organization()
            validation = .valid(org.organizationName)
            if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.name = org.organizationName
            }
        } catch {
            validation = .invalid(error.localizedDescription)
        }
    }
}

#Preview { SettingsView() }
