//
//  AccountEditor+Logic.swift
//  coderpad
//

import SwiftUI

extension AccountEditor {
    /// Width of the right-aligned label column, sized to hold the longest label
    /// ("Description") so every field starts at the same x — the Mail look.
    var labelColumnWidth: CGFloat {
        84
    }

    /// One Mail-style row: a right-aligned label paired with a left-aligned field.
    func fieldRow(_ label: String,
                  @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: labelColumnWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Bridges the optional `baseURL` to the text field: an empty field means
    /// "use the default", which we store as `nil` rather than an empty string.
    var baseURLBinding: Binding<String> {
        Binding(
            get: { draft.baseURL ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.baseURL = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    var isValidated: Bool {
        if case .valid = validation { return true }
        return false
    }

    /// Bridges the optional tint to a `ColorPicker`: an unset tint shows the
    /// account's current default swatch, and picking any color stores its hex.
    var tintColorBinding: Binding<Color> {
        Binding(
            get: { draft.tintColor ?? draft.avatarTint },
            set: { draft.tintHex = $0.hexString }
        )
    }

    /// Whether the account carries a custom icon or tint, gating the Reset control.
    var hasCustomAppearance: Bool {
        draft.iconSymbol != nil || draft.tintHex != nil
    }

    /// Whether the editor is modifying a saved account (vs. adding a new one); the
    /// Delete callback is supplied only in that case.
    var isEditing: Bool {
        onDelete != nil
    }

    /// Org member emails for the picker, including any already-saved email that the
    /// org list might not return, sorted for a stable order.
    var emailOptions: [String] {
        var emails = Set(orgUsers.map(\.email).filter { !$0.isEmpty })
        if !draft.userEmail.isEmpty { emails.insert(draft.userEmail) }
        return emails.sorted()
    }

    func emailLabel(_ email: String) -> String {
        if let name = orgUsers.first(where: { $0.email == email })?.name, !name.isEmpty {
            return "\(name) · \(email)"
        }
        return email
    }

    var validateDisabled: Bool {
        draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty || validation == .validating
    }

    @ViewBuilder
    var validateButton: some View {
        // When Save is available it owns the default action (Return); otherwise Validate
        // is the primary call to action, so only one button claims the shortcut.
        if canSave {
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

    /// Whether the draft has a non-empty user email. Required to save: the email
    /// identifies "you" for the My Pads/My Questions filters and the menu bar.
    var hasEmail: Bool {
        !draft.userEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A saved account whose key and server URL are untouched can be re-saved without
    /// re-validating, so edits to the Description or email persist freely; a new account
    /// or a changed credential still requires a successful validation first. In every
    /// case a user email is required — a legacy account saved without one must be
    /// re-validated (which reveals the picker and auto-detects the email) before it
    /// can be saved again.
    var canSave: Bool {
        guard hasEmail else { return false }
        return isValidated || (isEditing && draft.apiKey == initialAPIKey && draft.baseURL == initialBaseURL)
    }

    @ViewBuilder
    var saveButton: some View {
        let save = {
            finalizeNameIfNeeded()
            onSave(draft)
        }
        if canSave {
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Save", action: save)
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }

    func finalizeNameIfNeeded() {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            if case let .valid(org) = validation {
                draft.name = org
            } else {
                draft.name = "Account"
            }
        }
    }

    @ViewBuilder
    var validationBanner: some View {
        switch validation {
        case .idle, .valid:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating API key…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case let .invalid(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout)
        }
    }

    /// A non-blocking, amber note shown when the key validated against the org but
    /// lacks the scope for one or more feature endpoints.
    @ViewBuilder
    var scopeWarningBanner: some View {
        if let scopeWarning {
            Label(scopeWarning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout)
        }
    }

    func validate() async {
        validation = .validating
        scopeWarning = nil
        do {
            let client = CoderPadClient(apiKey: draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                        baseURL: draft.resolvedBaseURL)
            let org = try await client.organization()
            orgUsers = org.users
            if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.name = org.organizationName
            }
            // Pre-select the signed-in user's email. The default /api/pads/ endpoint
            // is scoped to the API key owner, so the dominant owner email on their pads
            // is "you" — detect it directly rather than making the user pick. Fall back
            // to the single-user org case, then to the manual picker. This runs while
            // still in the validating state so the spinner covers the email retrieval.
            if draft.userEmail.isEmpty {
                if let detected = await detectUserEmail(client: client) {
                    draft.userEmail = detected
                } else if org.users.count == 1 {
                    draft.userEmail = org.users.first?.email ?? ""
                }
            }
            validation = .valid(org.organizationName)
            // The key reaches the org; now surface any feature endpoints it isn't
            // scoped for, as a non-blocking note (the account still saves).
            scopeWarning = await missingScopesWarning(client: client)
        } catch {
            validation = .invalid(friendlyValidationMessage(for: error))
        }
    }

    /// After the key proves it can reach the org, probe the main read endpoints
    /// with one lightweight request each and report any that return a 403, so the
    /// user learns up front that, e.g., Questions will be empty rather than hitting
    /// a silent empty section later. Non-blocking: the account still validates and
    /// saves. Network/other errors are not treated as missing scopes.
    func missingScopesWarning(client: CoderPadClient) async -> String? {
        func authorized(_ probe: @escaping () async throws -> Void) async -> Bool {
            do {
                try await probe()
                return true
            } catch let error as CoderPadError where error.isUnauthorized {
                return false
            } catch {
                return true
            }
        }
        /// One page proves read access without pulling the whole list.
        func firstPage(_ stream: AsyncThrowingStream<[some Any], Error>) async throws {
            for try await _ in stream {
                return
            }
        }
        async let padsOK = authorized { try await firstPage(client.listPadsIncrementally()) }
        async let questionsOK = authorized { try await firstPage(client.listQuestionsIncrementally()) }
        async let quotaOK = authorized { _ = try await client.quota() }

        var missing: [String] = []
        if await padsOK == false { missing.append("Pads") }
        if await questionsOK == false { missing.append("Questions") }
        if await quotaOK == false { missing.append("Quota") }
        guard !missing.isEmpty else { return nil }
        let list = missing.joined(separator: ", ")
        return "This key works, but isn't authorized for: \(list). Those sections may be empty."
    }

    /// Derives the signed-in user's email from their own pads. `/api/pads/` is scoped
    /// to the API key owner, so the most common owner email on the first page is "you".
    /// Returns nil if the user has no pads yet (e.g. a brand-new account), letting the
    /// caller fall back to the manual picker. Non-fatal: validation already succeeded.
    func detectUserEmail(client: CoderPadClient) async -> String? {
        do {
            for try await page in client.listPadsIncrementally() {
                let emails = page.map(\.ownerEmail).filter { !$0.isEmpty }
                guard !emails.isEmpty else { return nil }
                let counts = Dictionary(emails.map { ($0, 1) }, uniquingKeysWith: +)
                return counts.max { $0.value < $1.value }?.key
            }
        } catch {
            // Ignore: the picker remains available as a fallback.
        }
        return nil
    }

    func friendlyValidationMessage(for error: Error) -> String {
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
                return """
                CoderPad returned something unexpected. Try again, and if it keeps happening, \
                regenerate the key.
                """
            case .network:
                return api.errorDescription ?? "Couldn't reach CoderPad. Check your internet connection and try again."
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Couldn't reach CoderPad. Check your internet connection and try again."
        }
        return "Couldn't validate this key. Try again."
    }
}

/// A searchable replacement for a long `Picker` of organization members. Shows the
/// current selection as a button; tapping opens a popover with a search field that
/// filters the (potentially large) member list so you don't scroll a huge menu.
struct OrgMemberPicker: View {
    /// Empty means no member is picked yet — the "Unset" row.
    @Binding var selection: String
    let options: [String]
    let label: (String) -> String

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selection.isEmpty ? "Unset" : label(selection))
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
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
                        memberRow(email: "", title: "Unset")
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
    private func memberRow(email: String, title: String) -> some View {
        let isSelected = email == selection
        Button {
            selection = email
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(email.isEmpty ? .secondary : .primary)
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
