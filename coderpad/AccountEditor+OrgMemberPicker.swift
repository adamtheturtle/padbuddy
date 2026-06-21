//
//  AccountEditor+OrgMemberPicker.swift
//  coderpad
//

import SwiftUI

/// A searchable replacement for a long `Picker` of organization members. Shows the
/// current selection as a button; tapping opens a popover with a search field that
/// filters the (potentially large) member list so you don't scroll a huge menu.
struct OrgMemberPicker: View {
    /// Empty means no member is picked yet — shown as "Unset" on the button, but the
    /// list offers no way to re-blank a selection since the email is required to save.
    @Binding var selection: String
    let options: [String]
    let label: (String) -> String
    /// Whether the org's member list is still being fetched. Shown as a row inside
    /// the popover rather than beside the field, so opening the editor doesn't shift
    /// the layout while the list loads (#497).
    var isLoading: Bool = false
    /// Fired when the popover opens, so the caller can lazily fetch the member list
    /// on demand instead of eagerly on appear — which avoids the on-open flash.
    var onOpen: (() -> Void)?

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
            onOpen?()
        } label: {
            HStack {
                Text(selection.isEmpty ? String(localized: "Unset") : label(selection))
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
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
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Search members", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.self) { email in
                            memberRow(email: email, title: label(email))
                        }
                        // While the full member list is still loading, the only option
                        // is the saved email, so tell the user more are on the way.
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Loading members…")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                            .padding(8)
                        } else if filtered.isEmpty {
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
