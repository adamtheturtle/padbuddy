//
//  AccountEditor.swift
//  coderpad
//

import BuddyDesignSystem
import LocalAuthentication
import SwiftUI

/// The validation status type now lives in BuddyDesignSystem (shared with RankBuddy's
/// account editor). The org name that used to ride on `.valid` is held separately in
/// `AccountEditor.validatedOrgName`, since the shared `.valid` is detail-free.
typealias ValidationState = CredentialValidationState

struct AccountEditor: View {
    @State var draft: Account
    @State var persistedDraft: Account
    let initialName: String
    /// When true, the editor is embedded inline in the Accounts pane (Mail-style)
    /// rather than presented as a modal sheet: it drops the fixed sheet frame, hides
    /// Cancel for saved accounts, and shows the "Switch to This Account" header control.
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
    @State var validation: ValidationState = .idle
    /// The organization name resolved by a successful key validation, used as the default
    /// account name. Held here since the shared `.valid` validation state is detail-free.
    @State var validatedOrgName: String?
    @State var orgUsers: [OrganizationUser] = []
    /// True while the saved account's organization members are loading.
    @State var isLoadingMembers = false
    @State var memberLoadError: String?
    /// A non-blocking note when the key reaches the org but isn't authorized for
    /// one or more feature endpoints (a 403), so the user learns up front that a
    /// section will be empty rather than discovering it later. See `missingScopesWarning`.
    @State var scopeWarning: String?
    /// The running validation, held so editing the key or Server URL cancels it.
    /// Validation ends with three concurrent scope probes. Their results were already
    /// discarded when superseded, but the requests kept running, so rapid editing left
    /// a pile of in-flight probes against credentials the user had already replaced
    /// (#2194). Cancelling the task cancels them: `async let` children inherit it.
    @State var validationTask: Task<Void, Never>?
    @State var validationThrottle = ValidationThrottle()
    @State var nameEditGeneration = 0
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
    /// Debounces autosave for saved-account edits so typing in text fields does not
    /// write the account store on every keystroke.
    @State var liveCommitTask: Task<Void, Never>?
    #if !os(macOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    init(initial: Account,
         embedded: Bool = false,
         isCurrent: Bool = false,
         onUse: (() -> Void)? = nil,
         onSave: @escaping (Account) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: (() -> Void)? = nil,
         onAppearanceChange: ((String?, String?) -> Void)? = nil) {
        _draft = State(initialValue: initial)
        _persistedDraft = State(initialValue: initial.normalizedForStorage)
        _screenExpanded = State(
            initialValue: !((initial.screenApiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
        initialName = initial.name
        self.embedded = embedded
        self.isCurrent = isCurrent
        self.onUse = onUse
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onAppearanceChange = onAppearanceChange
    }

    /// Reveals or hides the Interview API key. Hiding is immediate; revealing is gated
    /// behind a Touch ID / password check.
    func toggleReveal() {
        toggleReveal(of: $revealKey, reason: "Reveal your saved CoderPad API key")
    }

    /// Reveals or hides the optional Screen API key, with the same biometric gating.
    func toggleScreenReveal() {
        toggleReveal(of: $revealScreenKey, reason: "Reveal your saved CoderPad Screen API key")
    }

    /// Shared reveal/hide logic for a secure key field. Hiding is immediate; revealing
    /// requires a successful device owner authentication check.
    private func toggleReveal(of revealed: Binding<Bool>, reason: String) {
        if revealed.wrappedValue { revealed.wrappedValue = false; return }

        Task {
            if await authenticateForReveal(reason: reason) {
                revealed.wrappedValue = true
            }
        }
    }

    private func authenticateForReveal(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// On iPad, the modal Add-account sheet presents Cancel/Save in the navigation bar
    /// (the standard iOS modal-editor layout) rather than as an inline button row at the
    /// bottom of the form. macOS keeps its Mail-style inline buttons, and the embedded
    /// editor (a detail pane already inside the Settings NavigationStack) keeps its inline
    /// Save too. (#584)
    private var usesNavigationBarActions: Bool {
        #if os(macOS)
            false
        #else
            !embedded
        #endif
    }

    var body: some View {
        #if os(macOS)
            editorContent
        #else
            if usesNavigationBarActions {
                NavigationStack {
                    // Wrap the form in a ScrollView so it sits under (and scrolls
                    // behind) the navigation bar with a proper opaque scroll edge.
                    // A bare VStack leaves the bar translucent, letting the first
                    // field row draw over the "Add account" title and Save button.
                    // It also keeps the tall form reachable when the keyboard is up.
                    ScrollView {
                        editorContent
                    }
                    .navigationTitle("Add account")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", action: onCancel)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveNow() }
                                .disabled(!canSave)
                        }
                    }
                }
            } else {
                editorContent
            }
        #endif
    }

    /// The header row: an optional "Add account" title and the Use/Current control.
    /// Skipped entirely when it would be empty — on the iPad modal sheet the title
    /// moves to the nav bar and there's no Use control (#584).
    @ViewBuilder
    private var headerRow: some View {
        if (!embedded && !usesNavigationBarActions) || onUse != nil {
            HStack {
                // Only the modal Add sheet carries a title; the embedded editor shows
                // the account's identity in the sidebar already, so it omits one and
                // leads with the Use/Current control instead. On iPad the nav bar
                // carries the title, so the in-body one is dropped there (#584).
                if !embedded, !usesNavigationBarActions {
                    Text("Add account").font(.title3.bold())
                }
                Spacer()
                if let onUse {
                    if isCurrent {
                        Label("Current", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Button("Switch to This Account", action: onUse)
                            .buttonStyle(.glassProminent)
                            .help("Switch from All Accounts or another account to this account.")
                    }
                }
            }
            // Reserve the button's height so swapping it for the shorter "Current"
            // label between accounts doesn't shift the rest of the form.
            .frame(minHeight: 24)
        }
    }

    /// The bottom action row: Delete, Cancel, Validate, and Save, each shown
    /// according to the editor's mode (embedded / modal / iPad nav-bar actions).
    private var actionRow: some View {
        HStack {
            if onDelete != nil {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
                .help("Remove this account and its stored API key from this Mac.")
                .accessibilityLabel("Delete account")
            }
            Spacer()
            // The iPad modal sheet hosts Cancel/Save in the navigation bar, so the
            // inline row drops them and keeps only Validate (and Delete) there (#584).
            if !usesNavigationBarActions {
                // A saved account embedded inline has no Cancel: selecting away simply
                // discards unsaved edits, the way Mail's account pane works.
                if !(embedded && onDelete != nil) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            validateButton
            // Saved embedded accounts autosave their edits, so Add-account is the only
            // account flow that still needs an explicit Save button.
            if !usesNavigationBarActions, !commitsLive {
                saveButton
            }
        }
    }

    /// The form column and its frame. Splitting the `.onChange`/dialog modifiers off
    /// into `editorContent` keeps each chained `some View` expression under the
    /// type-checker's 250ms budget (see warnings-as-errors timing). The frame metrics
    /// are explicitly-typed locals so the `embedded ? nil : 460` ternaries don't make
    /// the checker re-infer `CGFloat?` across the whole chain.
    private var editorForm: some View {
        let minWidth: CGFloat? = (embedded || usesCompactAccountEditorLayout) ? nil : 460
        let minHeight: CGFloat? = embedded ? nil : 320
        let maxWidth: CGFloat? = usesCompactAccountEditorLayout ? .infinity : nil
        let maxHeight: CGFloat? = embedded ? .infinity : nil
        return VStack(alignment: .leading, spacing: 14) {
            headerRow
            // A flat, Mail-style pane: a right-aligned label column with left-aligned,
            // bordered fields beside it — rather than a grouped form that pushes values
            // to the trailing edge.
            formFields

            validationBanner
            scopeWarningBanner

            actionRow
        }
        .padding()
        .frame(minWidth: minWidth, maxWidth: maxWidth,
               minHeight: minHeight, maxHeight: maxHeight, alignment: .top)
    }

    /// The form plus the credential watchers: a changed Interview/Screen key or server
    /// URL clears any prior validation, and (on iPad) live-commits editable fields. Kept
    /// separate from `editorContent` so neither chained `some View` expression blows the
    /// type-checker's 250ms budget.
    private var editorWatchers: some View {
        editorForm
            .onChange(of: draft.apiKey) { _, _ in cancelValidation() }
            .onChange(of: draft.baseURL) { _, _ in cancelValidation() }
            // A changed Screen key or region invalidates any prior Screen validation result.
            // Screen credentials don't gate `canSave`, so saved accounts autosave them too.
            .onChange(of: draft.screenApiKey) { _, _ in screenValidation = .idle; commitLiveEdit() }
            .onChange(of: draft.screenRegion) { _, _ in screenValidation = .idle; commitLiveEdit() }
            // Saved-account autosave: persist Description / Your Email edits after typing
            // settles, and persist a re-validated key or server URL when validation flips
            // to `.valid` (which re-enables `canSave`). A no-op for the modal Add sheet.
            .onChange(of: draft.name) { _, _ in descriptionChanged() }
    }

    private var editorContent: some View {
        editorWatchers
            .onChange(of: draft.userEmail) { _, _ in commitLiveEdit() }
            .onChange(of: validation) { _, _ in commitLiveEdit() }
            // Icon and tint are cosmetic, so persist them the moment they change rather
            // than waiting for Save (which gates on validation/email for the credentials).
            .onChange(of: draft.iconSymbol) { _, _ in onAppearanceChange?(draft.iconSymbol, draft.tintHex) }
            .onChange(of: draft.tintHex) { _, _ in onAppearanceChange?(draft.iconSymbol, draft.tintHex) }
            .onDisappear {
                liveCommitTask?.cancel()
                persistLiveEditIfPossible()
            }
            .alert("Delete this account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) {
                    // Stop any debounced autosave before removing the account, so it
                    // cannot re-create it a moment later (#2191).
                    liveCommitTask?.cancel()
                    liveCommitTask = nil
                    onDelete?()
                }
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
                            in: RoundedRectangle(cornerRadius: Radius.chip))
                .overlay(RoundedRectangle(cornerRadius: Radius.chip)
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
