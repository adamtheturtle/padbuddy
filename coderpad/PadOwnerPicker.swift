//
//  PadOwnerPicker.swift
//  coderpad
//

import SwiftUI

/// A searchable replacement for a long `Picker` of questions. Shows the current
/// selection as a button; tapping opens a popover with a search field that filters
/// the (potentially large) question list so you don't scroll a huge menu.
struct SearchableQuestionPicker: View {
    @Binding var selection: Int?
    let questions: [Question]

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private func title(for question: Question) -> String {
        question.title.isEmpty ? "#\(question.id)" : question.title
    }

    private var selectedTitle: String {
        guard let id = selection,
              let question = questions.first(where: { $0.id == id }) else { return String(localized: "None") }

        return title(for: question)
    }

    private var filtered: [Question] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return questions }

        return questions.filter { title(for: $0).localizedCaseInsensitiveContains(trimmed) }
    }

    #if os(iOS)
    private var usesSheetPresentation: Bool {
        horizontalSizeClass == .compact
    }
    #else
    private var usesSheetPresentation: Bool { false }
    #endif

    var body: some View {
        #if os(iOS)
        if usesSheetPresentation {
            button
                .sheet(isPresented: $isPresented) {
                    NavigationStack {
                        pickerContent(maxListHeight: nil)
                            .navigationTitle("Question")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { isPresented = false }
                                }
                            }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .onAppear { searchFocused = true }
                }
        } else {
            popoverButton
        }
        #else
        popoverButton
        #endif
    }

    private var popoverButton: some View {
        button
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                pickerContent(maxListHeight: 240)
                    .frame(width: 320)
                    .onAppear { searchFocused = true }
            }
    }

    private var button: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selectedTitle)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Decorative dropdown indicator: the button's text already names
                    // the selection, so VoiceOver shouldn't read the symbol on top.
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
        .buttonStyle(.bordered)
    }

    private func pickerContent(maxListHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            TextField("Search questions", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    questionRow(id: nil, title: String(localized: "None"))
                    ForEach(filtered) { question in
                        questionRow(id: question.id, title: title(for: question))
                    }
                    if filtered.isEmpty {
                        Text("No questions match “\(query)”")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: maxListHeight)
        }
    }

    @ViewBuilder
    private func questionRow(id: Int?, title: String) -> some View {
        let isSelected = id == selection
        Button {
            selection = id
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(id == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, usesSheetPresentation ? 12 : 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

private extension String {
    /// `nil` when the string is empty, otherwise itself — for collapsing optional
    /// names that arrive as empty strings into a true "missing" value.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Picks the new pad's owner. An empty `ownerEmail` means "let the API default to
/// the key's owner"; the picker surfaces that as a concrete, named "Default" row
/// (resolved from the configured account) rather than an abstract placeholder.
///
/// The search field doubles as free-text email entry: orgs where the key isn't an
/// owner may return no member list, and you may want to assign an owner who isn't
/// listed — typing any address offers a "Use …" row, so the field is never a dead
/// end when `users` is empty.
struct SearchableOwnerPicker: View {
    @Binding var ownerEmail: String
    let users: [OrganizationUser]
    /// The configured account email, used only to label the Default row with who
    /// the key owner is. Pads are still created with an empty owner so the server
    /// resolves the true key owner.
    let keyOwnerEmail: String?

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.orgDirectory) private var directory
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var trimmedOwner: String {
        ownerEmail.trimmingCharacters(in: .whitespaces)
    }

    private func displayName(forEmail email: String) -> String? {
        // Fall back to the app-wide org directory (seeded from disk, so already
        // populated) when `users` hasn't loaded yet. Without it the closed button
        // showed the raw email on first render and flashed to the name a moment
        // later, once this pad's `orgUsers` fetch returned.
        users.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.name?
            .nilIfEmpty
            ?? directory.name(for: email)
    }

    /// The current account's email, when known — used to recognize an explicitly
    /// self-owned pad (e.g. when editing) and to label the "Me" row by name.
    private var selfEmail: String? {
        keyOwnerEmail?.nilIfEmpty
    }

    /// True when the picker already holds the current account's own email.
    private var isSelfSelected: Bool {
        guard let selfEmail else { return false }

        return selfEmail.caseInsensitiveCompare(trimmedOwner) == .orderedSame
    }

    /// Label for the "Me" choice: the account name when we know it, else just "Me".
    private var meLabel: String {
        guard let email = selfEmail else { return String(localized: "Me") }

        return String(localized: "\(displayName(forEmail: email) ?? email) (Me)",
                      comment: "Owner-picker label for the signed-in user, e.g. \"Ada Lovelace (Me)\"")
    }

    /// Subtitle for the "Me" row: the resolved key owner when known, otherwise a
    /// short explanation that an empty owner means the account holder.
    private var meSubtitle: String {
        guard let email = selfEmail else { return String(localized: "Owned by your account (the API key owner)") }

        if let name = displayName(forEmail: email) { return "\(name) · \(email)" }
        return email
    }

    /// The label shown on the closed picker button. An empty owner means the pad is
    /// owned by the key owner — i.e. you — so it reads as "Me".
    private var selectedLabel: String {
        if trimmedOwner.isEmpty || isSelfSelected { return meLabel }
        return displayName(forEmail: trimmedOwner) ?? trimmedOwner
    }

    private var filteredUsers: [OrganizationUser] {
        // Exclude self — it's offered as a pinned "Me" row at the top instead.
        let members = users.filter {
            $0.email.caseInsensitiveCompare(selfEmail ?? "") != .orderedSame
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return members }

        return members.filter {
            $0.email.localizedCaseInsensitiveContains(trimmed)
                || ($0.name?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// A typed address that isn't already an existing member — offered as a
    /// "Use …" row so free-text assignment still works.
    private var customEmailCandidate: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return nil }
        guard !users.contains(where: { $0.email.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }

        return trimmed
    }

    #if os(iOS)
    private var usesSheetPresentation: Bool {
        horizontalSizeClass == .compact
    }
    #else
    private var usesSheetPresentation: Bool { false }
    #endif

    var body: some View {
        #if os(iOS)
        if usesSheetPresentation {
            button
                .sheet(isPresented: $isPresented) {
                    NavigationStack {
                        pickerContent(maxListHeight: nil)
                            .navigationTitle("Owner")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { isPresented = false }
                                }
                            }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .onAppear { searchFocused = true }
                }
        } else {
            popoverButton
        }
        #else
        popoverButton
        #endif
    }

    private var popoverButton: some View {
        button
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                pickerContent(maxListHeight: 240)
                    .frame(width: 320)
                    .onAppear { searchFocused = true }
            }
    }

    private var button: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selectedLabel)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Decorative dropdown indicator: the button's text already names
                    // the selection, so VoiceOver shouldn't read the symbol on top.
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
    }

    private func pickerContent(maxListHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            TextField("Search members or enter email", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Pinned, always-present "Me" shortcut. An empty owner makes
                    // the server assign the pad to the key owner — you — so this
                    // works even when the account's email was never detected.
                    ownerRow(email: "",
                             primary: meLabel,
                             secondary: meSubtitle,
                             isMuted: false)

                    Divider()

                    ForEach(filteredUsers) { user in
                        ownerRow(email: user.email,
                                 primary: user.name?.nilIfEmpty ?? user.email,
                                 secondary: user.name?.nilIfEmpty == nil ? nil : user.email,
                                 isMuted: false)
                    }

                    if let custom = customEmailCandidate {
                        ownerRow(email: custom,
                                 primary: String(localized: "Use “\(custom)”"),
                                 secondary: nil,
                                 isMuted: false)
                    }

                    if filteredUsers.isEmpty, customEmailCandidate == nil,
                       !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("No members match “\(query)”")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: maxListHeight)
        }
    }

    @ViewBuilder
    private func ownerRow(email: String, primary: String, secondary: String?, isMuted: Bool) -> some View {
        let isSelected = email.caseInsensitiveCompare(trimmedOwner) == .orderedSame
        Button {
            ownerEmail = email
            query = ""
            isPresented = false
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(primary)
                        .foregroundStyle(isMuted ? .secondary : .primary)
                        .lineLimit(1)
                    if let secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, usesSheetPresentation ? 12 : 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}
