//
//  CreatePadIntent.swift
//  coderpad
//
//  The app-target twin of the widget extension's `CreatePadIntent`
//  (`RecentPadsWidget/CreatePadIntent.swift`), kept byte-for-byte in lock-step with
//  it, exactly like the two `WidgetSharedStore` copies.
//
//  Why it has to exist in BOTH targets: a Control Center / menu-bar control can only
//  open its host app when the control's App Intent is a member of the app target too,
//  so the app's App Intents metadata lists it (see "Creating controls to perform
//  actions across the system → Open your app with a control" in WidgetKit's docs).
//  The widget's interactive `Button(intent:)` opens the app from the extension alone
//  via `openAppWhenRun`, which is why the widget's New Pad button worked while the
//  control did nothing (#485). The control still runs the extension's copy and records
//  the request through the App Group; this twin is what makes the system bring the app
//  forward so `applicationDidBecomeActive` can consume it.
//

import AppIntents

/// Creates a new pad straight from the widget or the Control Center / menu-bar
/// control. It records the request in the shared App Group and opens the app, which
/// performs it on activation (see the app's `applicationDidBecomeActive`).
///
/// This replaces `OpenURLIntent(coderpad://new-pad)`: `OpenURLIntent` only opens
/// universal (https) links, never a custom URL scheme, so it silently did nothing
/// (#456, #485). An interactive `Button(intent:)` also works on the small widget
/// family, where `Link` is ignored — so this is the only mechanism that puts a
/// working New Pad button on every family and on the control.
/// Computed (not stored) statics so they're concurrency-safe under Swift 6 strict
/// checking, matching `RecentPadsConfigurationIntent`.
struct OpenPadIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Open Pad"
    }

    static var description: IntentDescription {
        IntentDescription("Open a CoderPad pad.")
    }

    static var openAppWhenRun: Bool {
        true
    }

    @Parameter(title: "Pad ID")
    var id: String

    @Parameter(title: "Account")
    var account: String?

    init() {
        id = ""
        account = nil
    }

    init(id: String, account: String?) {
        self.id = id
        self.account = account
    }

    func perform() async throws -> some IntentResult {
        WidgetSharedStore.requestOpenPad(id: id, account: account)
        return .result()
    }
}

struct CreatePadIntent: AppIntent {
    static var title: LocalizedStringResource {
        "New Pad"
    }

    static var description: IntentDescription {
        IntentDescription("Create a new CoderPad pad.")
    }

    /// Bring the app to the front when run, so the create sheet appears.
    static var openAppWhenRun: Bool {
        true
    }

    /// The account to switch to first (its UUID string), when the button was
    /// configured to seed from a favourite question; nil creates a blank pad in the
    /// current account. The seed question's id travels alongside it.
    @Parameter(title: "Account")
    var account: String?

    @Parameter(title: "Question")
    var question: Int?

    init() {}

    init(account: String?, question: Int?) {
        self.account = account
        self.question = question
    }

    func perform() async throws -> some IntentResult {
        WidgetSharedStore.requestNewPad(account: account, question: question)
        return .result()
    }
}
