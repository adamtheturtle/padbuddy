//
//  SettingsView.swift
//  coderpad
//

import SwiftUI

struct SettingsView: View {
    @State private var store = AccountsStore.shared
    @State private var editingAccount: Account?
    @State private var selectedAccountID: UUID?

    var body: some View {
        TabView {
            accountsTab
                .padding(20)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            menuBarTab
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            Text("Accounts").font(.headline)
                .padding(.bottom, 8)

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
                    #if DEBUG
                    Button("Try Demo") {
                        store.addDemoIfMissing()
                    }
                    #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedAccountID) {
                    ForEach(store.accounts) { account in
                        AccountRow(
                            account: account,
                            isCurrent: account.id == store.currentAccountID,
                            onMakeCurrent: { store.currentAccountID = account.id }
                        )
                        .tag(account.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editingAccount = account }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(maxHeight: .infinity)

                HStack(spacing: 4) {
                    Button {
                        editingAccount = Account(name: "", apiKey: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add account")
                    .buttonStyle(.borderless)

                    Button {
                        if let id = selectedAccountID {
                            store.remove(id: id)
                            selectedAccountID = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Remove selected account")
                    .buttonStyle(.borderless)
                    .disabled(selectedAccountID == nil)

                    Divider().frame(height: 14)

                    Button {
                        if let id = selectedAccountID,
                           let account = store.accounts.first(where: { $0.id == id }) {
                            editingAccount = account
                        }
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit selected account")
                    .buttonStyle(.borderless)
                    .disabled(selectedAccountID == nil)

                    Spacer()

                    #if DEBUG
                    Button {
                        store.addDemoIfMissing()
                    } label: {
                        Label("Add Demo", systemImage: "wand.and.stars")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.accounts.contains(where: { $0.isMock }))
                    .help("Add a sandbox account backed by mock data. No key required (DEBUG builds only).")
                    #endif
                }
                .padding(.top, 6)
            }
        }
    }

    private var menuBarTab: some View {
        Form {
            Section {
                Stepper(value: Binding(
                    get: { UserDefaults.standard.integer(forKey: "menuBarTopN").nonZero ?? 10 },
                    set: { UserDefaults.standard.set($0, forKey: "menuBarTopN") }
                ), in: 3...30, step: 1) {
                    HStack {
                        Text("Recent pads in menu bar")
                        Spacer()
                        Text("\((UserDefaults.standard.integer(forKey: "menuBarTopN").nonZero ?? 10))")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Controls how many recent pads and questions appear in the menu bar item.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}

private struct AccountRow: View {
    let account: Account
    let isCurrent: Bool
    let onMakeCurrent: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(label: account.name, diameter: 30,
                         tint: account.isMock ? .purple : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name.isEmpty ? "Untitled account" : account.name)
                        .font(.callout.weight(.medium))
                    if account.isMock {
                        Text("Demo")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.18), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    if isCurrent {
                        Text("Current")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(account.isMock ? "Mock data, no key" : mask(account.apiKey))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isCurrent {
                Button("Use") { onMakeCurrent() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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
                Group {
                    if reveal {
                        TextField("API key", text: $draft.apiKey, prompt: Text("paste key"))
                    } else {
                        SecureField("API key", text: $draft.apiKey, prompt: Text("paste key"))
                    }
                }
                Toggle("Show key", isOn: $reveal)
                TextField("Name", text: $draft.name, prompt: Text("Auto-filled after validating"))
                GetAPIKeyLink()
                    .font(.callout)
            }
            .formStyle(.grouped)

            validationBanner

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Validate") { Task { await validate() } }
                    .disabled(draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || validation == .validating)
                Button("Save") {
                    finalizeNameIfNeeded()
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 320)
        .onChange(of: draft.apiKey) { _, _ in validation = .idle }
    }

    private func finalizeNameIfNeeded() {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            if case .valid(let org) = validation {
                draft.name = org
            } else {
                draft.name = "Account"
            }
        }
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
            Label("Valid: \(org)", systemImage: "checkmark.seal.fill")
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
            validation = .invalid(friendlyValidationMessage(for: error))
        }
    }

    private func friendlyValidationMessage(for error: Error) -> String {
        if let api = error as? CoderPadError {
            if api.isUnauthorized {
                return "CoderPad rejected this key. Double-check that it's the right one and hasn't been revoked."
            }
            switch api {
            case .missingAPIKey:
                return "Paste your CoderPad API key above."
            case .http:
                return "CoderPad couldn't verify the key right now. Try again in a moment."
            case .decode:
                return "CoderPad returned something unexpected. Try again, and if it keeps happening, regenerate the key."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach CoderPad. Check your internet connection and try again."
        }
        return "Couldn't validate this key. Try again."
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

#Preview { SettingsView() }
