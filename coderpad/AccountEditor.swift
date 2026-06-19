//
//  AccountEditor.swift
//  coderpad
//

import LocalAuthentication
import SwiftUI

enum ValidationState: Equatable {
    case idle
    case validating
    case valid(String)
    case invalid(String)
}

struct AccountEditor: View {
    @State var draft: Account
    let initialName: String
    /// When true, the editor is embedded inline in the Accounts pane (Mail-style)
    /// rather than presented as a modal sheet: it drops the fixed sheet frame, hides
    /// Cancel for saved accounts, and shows the "Use This Account" header control.
    let embedded: Bool
    /// Whether this account is the app's active one, shown as a badge in the header.
    let isCurrent: Bool
    /// Supplied only for a saved account in embedded mode; makes it the active account.
    let onUse: (() -> Void)?
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    /// Supplied only when editing a saved account; `nil` hides the Delete button (Add mode).
    let onDelete: (() -> Void)?
    /// Supplied for a saved account so icon/tint edits persist immediately, without
    /// the Save button: those are cosmetic and need no validation. `nil` (Add mode)
    /// keeps the appearance in the draft until the account is saved.
    let onAppearanceChange: ((_ iconSymbol: String?, _ tintHex: String?) -> Void)?
    /// The credentials the editor opened with. A saved account can be re-saved without
    /// re-validating as long as these are untouched (e.g. a Description-only change);
    /// changing either forces a fresh validation before Save re-enables.
    let initialAPIKey: String
    let initialBaseURL: String?
    @State var validation: ValidationState = .idle
    @State var orgUsers: [OrganizationUser] = []
    /// True while the background fetch of the org's member list (for a saved account,
    /// on open) is in flight — see `loadOrgMembersForEditing`.
    @State var isLoadingMembers = false
    /// A non-blocking note when the key reaches the org but isn't authorized for
    /// one or more feature endpoints (a 403), so the user learns up front that a
    /// section will be empty rather than discovering it later. See `missingScopesWarning`.
    @State var scopeWarning: String?
    @State var showDeleteConfirmation = false
    /// Reveals the API key as plain text on explicit request. The field is a
    /// `SecureField` by default so macOS offers password AutoFill suggestions;
    /// revealing it via a toggle (rather than on focus) keeps that intact.
    @State var revealKey = false
    /// Reveals the optional Screen API key as plain text, mirroring `revealKey`.
    @State var revealScreenKey = false
    /// Validation state of the optional Screen key, kept separate from the Interview
    /// key's `validation`: Screen is additive and never gates Save.
    @State var screenValidation: ValidationState = .idle
    // SwiftUI @State read only via its $-projected binding (DisclosureGroup).
    // periphery:ignore
    /// Whether the optional Screen credentials section is expanded. Starts open when
    /// the account already has a Screen key (so it's visible), collapsed otherwise so
    /// it doesn't clutter accounts that don't use Screen.
    @State var screenExpanded: Bool
    /// When set in General settings, revealing a saved key first requires a
    /// successful Touch ID (or password) check — see `toggleReveal`.
    @AppStorage(GeneralSettings.Key.requireBiometricsToRevealKey) var requireBiometricsToRevealKey = false

    init(initial: Account,
         embedded: Bool = false,
         isCurrent: Bool = false,
         onUse: (() -> Void)? = nil,
         onSave: @escaping (Account) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: (() -> Void)? = nil,
         onAppearanceChange: ((String?, String?) -> Void)? = nil) {
        _draft = State(initialValue: initial)
        _screenExpanded = State(
            initialValue: !((initial.screenApiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
        initialName = initial.name
        initialAPIKey = initial.apiKey
        initialBaseURL = initial.baseURL
        self.embedded = embedded
        self.isCurrent = isCurrent
        self.onUse = onUse
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onAppearanceChange = onAppearanceChange
    }

    /// Reveals or hides the Interview API key. Hiding is immediate; revealing is gated
    /// behind a Touch ID / password check when the user enabled that in General settings.
    func toggleReveal() {
        toggleReveal(of: $revealKey, reason: "Reveal your saved CoderPad API key")
    }

    /// Reveals or hides the optional Screen API key, with the same biometric gating.
    func toggleScreenReveal() {
        toggleReveal(of: $revealScreenKey, reason: "Reveal your saved CoderPad Screen API key")
    }

    /// Shared reveal/hide logic for a secure key field. Hiding is immediate; revealing
    /// is gated behind a Touch ID / password check when the user enabled that in General
    /// settings. If the device can't evaluate the policy (no biometrics and no passcode
    /// set), reveal anyway rather than lock the user out of their own key.
    private func toggleReveal(of revealed: Binding<Bool>, reason: String) {
        if revealed.wrappedValue { revealed.wrappedValue = false; return }
        guard requireBiometricsToRevealKey else { revealed.wrappedValue = true; return }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            revealed.wrappedValue = true
            return
        }

        Task {
            let success = await (try? context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )) ?? false
            if success { revealed.wrappedValue = true }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                // Only the modal Add sheet carries a title; the embedded editor shows
                // the account's identity in the sidebar already, so it omits one and
                // leads with the Use/Current control instead.
                if !embedded {
                    Text("Add account").font(.title3.bold())
                }
                Spacer()
                if let onUse {
                    if isCurrent {
                        Label("Current", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Button("Use This Account", action: onUse)
                            .help("Switch the app to this account.")
                    }
                }
            }
            // Reserve the button's height so swapping it for the shorter "Current"
            // label between accounts doesn't shift the rest of the form.
            .frame(minHeight: 24)
            // A flat, Mail-style pane: a right-aligned label column with left-aligned,
            // bordered fields beside it — rather than a grouped form that pushes values
            // to the trailing edge.
            formFields

            validationBanner
            scopeWarningBanner

            HStack {
                if onDelete != nil {
                    Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                        .help("Remove this account and its stored API key from this Mac.")
                }
                Spacer()
                // A saved account embedded inline has no Cancel: selecting away simply
                // discards unsaved edits, the way Mail's account pane works.
                if !(embedded && onDelete != nil) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                validateButton
                saveButton
            }
        }
        .padding()
        .frame(minWidth: embedded ? nil : 460, minHeight: embedded ? nil : 320,
               maxHeight: embedded ? .infinity : nil, alignment: .top)
        // For a saved account, pull the org's full member list as soon as the editor
        // opens so the "Your Email" picker offers everyone without a manual Validate.
        // Keyed on the account so switching accounts in the embedded pane re-fetches.
        .task(id: draft.id) { await loadOrgMembersForEditing() }
        .onChange(of: draft.apiKey) { _, _ in validation = .idle; scopeWarning = nil }
        .onChange(of: draft.baseURL) { _, _ in validation = .idle }
        // A changed Screen key or region invalidates any prior Screen validation result.
        .onChange(of: draft.screenApiKey) { _, _ in screenValidation = .idle }
        .onChange(of: draft.screenRegion) { _, _ in screenValidation = .idle }
        // Icon and tint are cosmetic, so persist them the moment they change rather
        // than waiting for Save (which gates on validation/email for the credentials).
        .onChange(of: draft.iconSymbol) { _, _ in onAppearanceChange?(draft.iconSymbol, draft.tintHex) }
        .onChange(of: draft.tintHex) { _, _ in onAppearanceChange?(draft.iconSymbol, draft.tintHex) }
        .confirmationDialog("Delete this account?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(initialName)” and its stored API key will be removed from this Mac. This can’t be undone.")
        }
    }
}

/// A compact row of curated SF Symbols for an account's avatar. The first option
/// (a "textformat" glyph) clears the symbol so the avatar falls back to initials.
struct AccountSymbolPicker: View {
    @Binding var selection: String?

    /// An adaptive grid wraps to the available width rather than forcing one long
    /// row that would push the whole settings pane wider than the window.
    private let columns = [GridItem(.adaptive(minimum: 28), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            symbolButton(nil, glyph: "textformat", help: "Use initials")
            ForEach(Account.iconSymbolChoices, id: \.self) { symbol in
                symbolButton(symbol, glyph: symbol, help: "Account icon")
            }
        }
    }

    @ViewBuilder
    private func symbolButton(_ value: String?, glyph: String, help: String) -> some View {
        let isSelected = selection == value
        Button {
            selection = value
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 13))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A compact row of curated tint swatches for an account's avatar. The first
/// swatch (`defaultColor`) clears the custom tint, falling back to the default.
struct AccountTintPicker: View {
    @Binding var selection: String?
    let defaultColor: Color

    /// Wraps to the available width so the swatches never overflow the pane.
    private let columns = [GridItem(.adaptive(minimum: 24), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            swatch(nil, color: defaultColor, help: "Default color")
            ForEach(Account.tintChoices, id: \.self) { hex in
                swatch(hex, color: Color(hex: hex) ?? .gray, help: "Account color")
            }
        }
    }

    @ViewBuilder
    private func swatch(_ value: String?, color: Color, help: String) -> some View {
        let isSelected = selection == value
        Button {
            selection = value
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.9 : 0.15),
                                         lineWidth: isSelected ? 2 : 0.5))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
