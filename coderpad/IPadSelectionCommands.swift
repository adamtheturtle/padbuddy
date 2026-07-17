//
//  IPadSelectionCommands.swift
//  coderpad
//
//  Selection-specific hardware-keyboard commands for iPad. These mirror the macOS
//  Pad, Question, and Screen command menus by using the same focused values and
//  AppNavigation routes, so the visible detail/list owns confirmation sheets and
//  read-only gating just as it does on macOS.
//

#if !os(macOS)
    import SwiftUI

    struct PadCommands: Commands {
        @FocusedValue(\.focusedPad) private var pad
        @FocusedValue(\.isReadOnly) private var isReadOnly
        @FocusedValue(\.padHasSavableCode) private var padHasSavableCode
        @AppStorage(PadSort.storageKey) private var sort: PadSort = .updatedDesc

        private var isEnded: Bool {
            guard let pad else { return false }

            return pad.isEnded
        }

        var body: some Commands {
            CommandMenu("Pad") {
                Button("Open Pad in Browser") {
                    guard let pad, let url = pad.webURL else { return }

                    BrowserSettings.openExternally(url)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(pad == nil)

                Button("Watch Playback") {
                    guard let pad else { return }

                    AppNavigation.shared.watchPlaybackPadID = pad.id
                }
                .keyboardShortcut("y", modifiers: [.command])
                .disabled(pad?.playbackURL == nil)

                Divider()

                Button("Edit Pad…") {
                    guard let pad else { return }

                    AppNavigation.shared.editPadID = pad.id
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(pad == nil || isReadOnly == true)

                Menu("Sort By") {
                    PadSortMenuContent(sort: $sort)
                }

                Divider()

                Button("Copy Pad ID") {
                    guard let pad else { return }

                    Clipboard.copy(pad.id)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(pad == nil)

                Button("Copy Pad URL") {
                    guard let pad else { return }

                    Clipboard.copy(pad.url)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(pad == nil)

                Button("Copy Pad Title") {
                    guard let pad else { return }

                    Clipboard.copy(pad.title.isEmpty ? pad.id : pad.title)
                }
                .disabled(pad == nil)

                Button("Copy as Markdown") {
                    guard let pad else { return }

                    let title = pad.title.isEmpty ? pad.id : pad.title
                    Clipboard.copy("[\(title)](\(pad.url))")
                }
                .disabled(pad == nil)

                if let url = pad?.webURL {
                    ShareLink("Share Pad…", item: url)
                } else {
                    Button("Share Pad…") {}.disabled(true)
                }

                Divider()

                Button("Save All Code…") {
                    guard let pad else { return }

                    AppNavigation.shared.saveCodePadID = pad.id
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(pad == nil || padHasSavableCode != true)

                Divider()

                Button("End Interview…") {
                    guard let pad else { return }

                    AppNavigation.shared.endPadID = pad.id
                }
                .disabled(pad == nil || isEnded || isReadOnly == true)

                Button("Delete Pad…") {
                    guard let pad else { return }

                    AppNavigation.shared.deletePadID = pad.id
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(pad == nil || isReadOnly == true)
            }
        }
    }

    struct QuestionCommands: Commands {
        @FocusedValue(\.focusedQuestion) private var question
        @FocusedValue(\.focusedQuestionIsFavorite) private var isFavorite
        @FocusedValue(\.focusedQuestionURL) private var questionURL
        @FocusedValue(\.isReadOnly) private var isReadOnly
        @AppStorage(QuestionSort.storageKey) private var sort: QuestionSort = .lastUsedDesc

        var body: some Commands {
            CommandMenu("Question") {
                Button("New Pad from Question") {
                    guard let question else { return }

                    AppNavigation.shared.createPadForQuestionID = question.id
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(question == nil || isReadOnly == true)

                Divider()

                Button("Edit Question…") {
                    guard let question else { return }

                    AppNavigation.shared.editQuestionID = question.id
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(question == nil || isReadOnly == true)

                Button(isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                    guard let question else { return }

                    AppNavigation.shared.toggleFavoriteQuestionID = question.id
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(question == nil)

                Menu("Sort By") {
                    QuestionSortMenuContent(sort: $sort)
                }

                Divider()

                Button("Copy Question ID") {
                    guard let question else { return }

                    Clipboard.copy(String(question.id))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(question == nil)

                Button("Copy Question URL") {
                    guard let questionURL else { return }

                    Clipboard.copy(questionURL.absoluteString)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(questionURL == nil)

                Button("Copy Question Title") {
                    guard let question else { return }

                    Clipboard.copy(question.displayTitle)
                }
                .disabled(question == nil)

                if let questionURL {
                    ShareLink("Share Question…", item: questionURL)
                } else {
                    Button("Share Question…") {}.disabled(true)
                }

                Divider()

                Button("Delete Question…") {
                    guard let question else { return }

                    AppNavigation.shared.deleteQuestionID = question.id
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(question == nil || isReadOnly == true)
            }
        }
    }

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
#endif
