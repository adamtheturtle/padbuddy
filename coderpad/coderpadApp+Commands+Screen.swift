#if os(macOS)
//
    //  coderpadApp+Commands+Screen.swift
    //  coderpad
//
    //  The "Screen" and "Window" menu commands, split out of
    //  `coderpadApp+Commands.swift` to keep each file under the length limit.
//

    import AppKit
    import SwiftUI

    /// Top-level "Screen" menu: acts on the selected Screen campaign or test session
    /// in the frontmost window. The Screen views publish focused action wrappers so
    /// command routing stays with the current selection and shares the same handlers
    /// as row context menus and toolbar buttons.
    struct ScreenCommands: Commands {
        @FocusedValue(\.focusedScreenCampaignAction) private var campaignAction
        @FocusedValue(\.focusedScreenTestAction) private var testAction
        @FocusedValue(\.focusedScreenInviteAction) private var inviteAction
        @FocusedValue(\.isReadOnly) private var isReadOnly

        var body: some Commands {
            CommandMenu("Screen") {
                Button("Show Test Sessions") {
                    campaignAction?.showTests()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(campaignAction == nil)

                Button("Invite Candidate…") {
                    inviteAction?.perform()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(inviteAction == nil || isReadOnly == true)

                Divider()

                Button("Open Test Session in New Window") {
                    testAction?.openWindow()
                }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(testAction == nil)

                Button("Resend Invitation") {
                    testAction?.resend()
                }
                .disabled(testAction?.canResendOrCancel != true || isReadOnly == true)

                Button("Cancel Invitation") {
                    testAction?.cancel()
                }
                .disabled(testAction?.canResendOrCancel != true || isReadOnly == true)

                Divider()

                Button("Copy Campaign Name") {
                    campaignAction?.copyName()
                }
                .disabled(campaignAction == nil)

                Button("Copy Test Session") {
                    testAction?.copySummary()
                }
                .disabled(testAction == nil)

                Divider()

                Button("Delete Test Session…") {
                    testAction?.delete()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(testAction == nil || isReadOnly == true)
            }
        }
    }

    /// Adds an "Open Main Window" item to the Window menu so the main window can be
    /// reopened after it's closed — the app keeps running with no windows (see
    /// `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`).
    struct WindowCommands: Commands {
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandGroup(after: .windowArrangement) {
                Button("Open Main Window") {
                    AppActivator.bringToFront()
                    openWindow(id: "main")
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
#endif
