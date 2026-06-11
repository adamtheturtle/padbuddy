//
//  SettingsView.swift
//  coderpad
//

import SwiftUI
import AppKit

/// Where a pad link opens when you activate it.
enum LinkDestination: String, CaseIterable, Identifiable {
    case inApp
    case external

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inApp: return "In-app browser"
        case .external: return "Default browser"
        }
    }
}

/// An installed app that can open http(s) links, shown in the "Default browser" picker.
struct InstalledBrowser: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// Browser-related preferences, stored in `UserDefaults` and read both by the
/// settings UI and by the link-opening call sites across the app. Centralizing
/// these here lets a single "Open" action honor the user's choice, which is why
/// the per-location "open in default browser" buttons are no longer needed.
enum BrowserSettings {
    enum Key {
        static let openLinksIn = "browser.openLinksIn"
        static let defaultBrowserBundleID = "browser.defaultBrowserBundleID"
        static let openInBackground = "browser.openInBackground"
    }

    static var openLinksIn: LinkDestination {
        LinkDestination(rawValue: UserDefaults.standard.string(forKey: Key.openLinksIn) ?? "") ?? .inApp
    }

    static var defaultBrowserBundleID: String? {
        UserDefaults.standard.string(forKey: Key.defaultBrowserBundleID)
    }

    static var openInBackground: Bool {
        UserDefaults.standard.bool(forKey: Key.openInBackground)
    }

    /// A representative URL used to discover http(s)-capable apps.
    private static let probeURL = URL(string: "https://app.coderpad.io")!

    /// Open a link in the user's chosen browser, honoring the background preference.
    @MainActor
    static func openExternally(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !openInBackground
        let appURL = defaultBrowserBundleID.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        } ?? NSWorkspace.shared.urlForApplication(toOpen: probeURL)
        if let appURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// http(s)-capable apps installed on this Mac, de-duplicated and sorted by name.
    static func installedBrowsers() -> [InstalledBrowser] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
        var seen = Set<String>()
        return urls.compactMap { appURL -> InstalledBrowser? in
            guard let id = Bundle(url: appURL)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return InstalledBrowser(bundleID: id, name: displayName(for: appURL))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name of the system's current default browser, e.g. "Safari".
    static func systemDefaultBrowserName() -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return "Safari" }
        return displayName(for: appURL)
    }

    private static func displayName(for appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}

struct SettingsView: View {
    @State private var store = AccountsStore.shared
    @State private var editingAccount: Account?
    @State private var selectedAccountID: UUID?

    var body: some View {
        TabView {
            accountsTab
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            browserTab
                .tabItem { Label("Browser", systemImage: "safari") }
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
                    .accessibilityLabel("Add account")

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
                    .accessibilityLabel("Remove selected account")

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
                    .accessibilityLabel("Edit selected account")

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
        .padding(20)
    }

    private var browserTab: some View {
        let openLinksIn = Binding(
            get: { BrowserSettings.openLinksIn },
            set: { UserDefaults.standard.set($0.rawValue, forKey: BrowserSettings.Key.openLinksIn) }
        )
        let defaultBrowser = Binding(
            get: { BrowserSettings.defaultBrowserBundleID },
            set: { UserDefaults.standard.set($0, forKey: BrowserSettings.Key.defaultBrowserBundleID) }
        )
        let openInBackground = Binding(
            get: { BrowserSettings.openInBackground },
            set: { UserDefaults.standard.set($0, forKey: BrowserSettings.Key.openInBackground) }
        )
        return Form {
            Section {
                Picker("Open links", selection: openLinksIn) {
                    ForEach(LinkDestination.allCases) { destination in
                        Text(destination.label).tag(destination)
                    }
                }
            }
            Section {
                Picker("Default browser", selection: defaultBrowser) {
                    Text("Use system default (\(BrowserSettings.systemDefaultBrowserName()))")
                        .tag(String?.none)
                    ForEach(BrowserSettings.installedBrowsers()) { browser in
                        Text(browser.name).tag(Optional(browser.bundleID))
                    }
                }
            }
            Section {
                Toggle("Open links in background", isOn: openInBackground)
            } footer: {
                Text("Please note that some third-party browsers do not support opening links in the background.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var menuBarTab: some View {
        let topN = Binding(
            get: { UserDefaults.standard.integer(forKey: "menuBarTopN").nonZero ?? 10 },
            set: { UserDefaults.standard.set($0, forKey: "menuBarTopN") }
        )
        return Form {
            Section {
                Stepper(value: topN, in: 3...30, step: 1) {
                    HStack {
                        Text("Recent pads in menu bar")
                        Spacer()
                        Text("\(topN.wrappedValue)")
                            .foregroundStyle(.secondary)
                    }
                }
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

            Spacer()

            if !isCurrent {
                Button("Use") { onMakeCurrent() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

enum ValidationState: Equatable {
    case idle
    case validating
    case valid(String)
    case invalid(String)
}

struct AccountEditor: View {
    @State var draft: Account
    let initialName: String
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    @State private var validation: ValidationState = .idle
    @State private var orgUsers: [OrganizationUser] = []
    @FocusState private var keyFieldFocused: Bool

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
                    if keyFieldFocused {
                        TextField("API key", text: $draft.apiKey, prompt: Text("key"))
                            .focused($keyFieldFocused)
                    } else {
                        SecureField("API key", text: $draft.apiKey, prompt: Text("key"))
                            .focused($keyFieldFocused)
                    }
                }
                if isValidated {
                    TextField("Name", text: $draft.name, prompt: Text("Auto-filled from your organization"))
                    LabeledContent("Your email") {
                        OrgMemberPicker(
                            selection: $draft.userEmail,
                            options: emailOptions,
                            label: emailLabel
                        )
                    }
                    .help("Used to show only your pads in the menu bar.")
                }
                GetAPIKeyLink()
                    .font(.callout)
            }
            .formStyle(.grouped)

            validationBanner

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                validateButton
                saveButton
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 320)
        .onChange(of: draft.apiKey) { _, _ in validation = .idle }
    }

    private var isValidated: Bool {
        if case .valid = validation { return true }
        return false
    }

    /// Org member emails for the picker, including any already-saved email that the
    /// org list might not return, sorted for a stable order.
    private var emailOptions: [String] {
        var emails = Set(orgUsers.map(\.email).filter { !$0.isEmpty })
        if let saved = draft.userEmail, !saved.isEmpty { emails.insert(saved) }
        return emails.sorted()
    }

    private func emailLabel(_ email: String) -> String {
        if let name = orgUsers.first(where: { $0.email == email })?.name, !name.isEmpty {
            return "\(name) · \(email)"
        }
        return email
    }

    private var validateDisabled: Bool {
        draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty || validation == .validating
    }

    @ViewBuilder
    private var validateButton: some View {
        if isValidated {
            Button("Validate") { Task { await validate() } }
                .buttonStyle(.bordered)
                .disabled(validateDisabled)
        } else {
            Button("Validate") { Task { await validate() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validateDisabled)
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        let save = {
            finalizeNameIfNeeded()
            onSave(draft)
        }
        if isValidated {
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Save", action: save)
                .buttonStyle(.bordered)
                .disabled(true)
        }
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
        case .idle, .valid:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating API key…").foregroundStyle(.secondary)
            }
            .font(.callout)
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
            orgUsers = org.users
            validation = .valid(org.organizationName)
            if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.name = org.organizationName
            }
            // Pre-select the signed-in user's email if it's unambiguous.
            if draft.userEmail == nil, org.users.count == 1 {
                draft.userEmail = org.users.first?.email
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

/// A searchable replacement for a long `Picker` of organization members. Shows the
/// current selection as a button; tapping opens a popover with a search field that
/// filters the (potentially large) member list so you don't scroll a huge menu.
private struct OrgMemberPicker: View {
    @Binding var selection: String?
    let options: [String]
    let label: (String) -> String

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selection.map(label) ?? "Not set")
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Search members", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        memberRow(email: nil, title: "Not set")
                        ForEach(filtered, id: \.self) { email in
                            memberRow(email: email, title: label(email))
                        }
                        if filtered.isEmpty {
                            Text("No members match “\(query)”")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .padding(8)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            .frame(width: 320)
            .onAppear { searchFocused = true }
        }
    }

    @ViewBuilder
    private func memberRow(email: String?, title: String) -> some View {
        let isSelected = email == selection
        Button {
            selection = email
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(email == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

#Preview { SettingsView() }
