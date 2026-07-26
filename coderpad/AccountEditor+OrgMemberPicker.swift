//
//  AccountEditor+OrgMemberPicker.swift
//  coderpad
//

import SwiftUI

/// A searchable replacement for a long `Picker` of organization members. Shows the
/// current selection as a button; tapping opens a popover with a search field that
/// filters the (potentially large) member list so you don't scroll a huge menu.
struct OrgMemberPicker: View {
    /// Empty means no member is picked yet — shown as "Unset" on the button.
    @Binding var selection: String
    let users: [OrganizationUser]
    /// Whether the org's member list is still being fetched. Shown as a row inside
    /// the popover rather than beside the field, so opening the editor doesn't shift
    /// the layout while the list loads (#497).
    var isLoading: Bool = false
    var loadError: String?
    /// Fired when the popover opens, so the caller can lazily fetch the member list
    /// on demand instead of eagerly on appear — which avoids the on-open flash.
    var onOpen: (() -> Void)?

    @State private var isPresented = false
    @State private var query = ""
    @State private var memberOptions: [MemberOption] = []
    /// Lowercased-email lookup rebuilt with `memberOptions`, so labeling the button
    /// and the per-keystroke "is this an existing member" check are dictionary hits
    /// instead of linear scans (#2277).
    @State private var optionsByEmailKey: [String: MemberOption] = [:]
    @FocusState private var searchFocused: Bool

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private struct MemberOption: Identifiable {
        var email: String
        var name: String?

        var id: String {
            email.lowercased()
        }

        var primary: String {
            name?.nilIfEmpty ?? email
        }

        var secondary: String? {
            name?.nilIfEmpty == nil ? nil : email
        }

        func matches(_ query: String) -> Bool {
            email.localizedCaseInsensitiveContains(query)
                || (name?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var trimmedSelection: String {
        selection.trimmingCharacters(in: .whitespaces)
    }

    private static func makeMemberOptions(users: [OrganizationUser], selection: String) -> [MemberOption] {
        var seenEmails = Set<String>()
        var options: [MemberOption] = []

        for user in users where !user.email.isEmpty {
            let key = user.email.lowercased()
            guard seenEmails.insert(key).inserted else { continue }

            options.append(MemberOption(email: user.email, name: user.name))
        }

        // A preserved selection only becomes a member-looking option when it is a
        // plausible address; surfacing a malformed saved value as a legitimate row
        // visually endorsed data that can't be saved (#2204). The button label
        // still shows the raw selection either way.
        let trimmedSelection = selection.trimmingCharacters(in: .whitespaces)
        if !trimmedSelection.isEmpty, EmailValidation.isPlausibleAddress(trimmedSelection) {
            let key = trimmedSelection.lowercased()
            if seenEmails.insert(key).inserted {
                options.append(MemberOption(email: trimmedSelection, name: nil))
            }
        }

        return options.sorted { lhs, rhs in
            lhs.primary.localizedCaseInsensitiveCompare(rhs.primary) == .orderedAscending
        }
    }

    private var selectedOption: MemberOption? {
        optionsByEmailKey[trimmedSelection.lowercased()]
    }

    private var selectedLabel: String {
        guard !trimmedSelection.isEmpty else { return String(localized: "Unset") }

        return selectedOption?.primary ?? trimmedSelection
    }

    private var filtered: [MemberOption] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return memberOptions }

        return memberOptions.filter { $0.matches(trimmedQuery) }
    }

    /// A typed address that isn't already an existing member — offered as a
    /// "Use …" row so the field still works before the org member list is loaded.
    private var customEmailCandidate: String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidation.isPlausibleAddress(trimmedQuery) else { return nil }
        guard optionsByEmailKey[trimmedQuery.lowercased()] == nil else { return nil }

        // Normalize the free-typed address (domain lowercased) so case variants of
        // the same mailbox compare and store consistently downstream (#2210).
        return EmailValidation.normalized(trimmedQuery)
    }

    private var pickerButton: some View {
        Button {
            // Each opening starts unfiltered: keeping the previous search text made
            // a reopened picker look mysteriously empty or incomplete (#2208).
            query = ""
            isPresented = true
            onOpen?()
        } label: {
            HStack {
                Text(selectedLabel)
                    .foregroundStyle(trimmedSelection.isEmpty ? .secondary : .primary)
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

    var body: some View {
        #if os(iOS)
            if horizontalSizeClass == .compact {
                pickerButton
                    .sheet(isPresented: $isPresented) {
                        NavigationStack {
                            memberList(showsInlineSearch: false)
                                .navigationTitle("Choose your email")
                                .navigationBarTitleDisplayMode(.inline)
                                .searchable(text: $query, prompt: "Search members or enter email")
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Cancel") { isPresented = false }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
                    .pickerLifecycle(users: users, selection: selection) { refreshMemberOptions() }
            } else {
                pickerButton
                    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                        memberList(showsInlineSearch: true)
                            .frame(width: 320, height: 300)
                    }
                    .pickerLifecycle(users: users, selection: selection) { refreshMemberOptions() }
            }
        #else
            pickerButton
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    memberList(showsInlineSearch: true)
                        .frame(width: 320, height: 300)
                }
                .pickerLifecycle(users: users, selection: selection) { refreshMemberOptions() }
        #endif
    }

    private func memberList(showsInlineSearch: Bool) -> some View {
        VStack(spacing: 0) {
            if showsInlineSearch {
                TextField("Search members or enter email", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)

                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { option in
                        memberRow(email: option.email,
                                  primary: option.primary,
                                  secondary: option.secondary,
                                  isMuted: false)
                    }

                    if let custom = customEmailCandidate {
                        memberRow(email: custom,
                                  primary: String(localized: "Use “\(custom)”"),
                                  secondary: nil,
                                  isMuted: false)
                    }

                    // While the full member list is still loading, the only option
                    // may be the saved email, so tell the user more are on the way.
                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .padding(8)
                    } else if isLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Fetching members…")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        .padding(8)
                    } else if filtered.isEmpty, customEmailCandidate == nil,
                              !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("No members match “\(query)”")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(8)
                    }
                }
            }
        }
        .onAppear {
            if showsInlineSearch { searchFocused = true }
        }
    }

    private func refreshMemberOptions() {
        memberOptions = Self.makeMemberOptions(users: users, selection: selection)
        optionsByEmailKey = Dictionary(
            memberOptions.map { ($0.email.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

private extension View {
    func pickerLifecycle(users: [OrganizationUser], selection: String,
                         refresh: @escaping () -> Void) -> some View {
        self
            // A single rebuild per real input change: the option list used to be
            // re-deduped and re-sorted from two onAppears, the button tap, and three
            // onChange handlers back-to-back on open (#2282). Comparing `users`
            // directly (Equatable) also avoids materializing a joined signature
            // string every render (#2274) and its unescaped-separator collisions (#2203).
            .onAppear { refresh() }
            .onChange(of: users) { _, _ in refresh() }
            .onChange(of: selection) { _, _ in refresh() }
    }
}

private extension OrgMemberPicker {
    @ViewBuilder
    private func memberRow(email: String, primary: String, secondary: String?, isMuted: Bool) -> some View {
        let isSelected = email.caseInsensitiveCompare(trimmedSelection) == .orderedSame
        Button {
            selection = email
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
