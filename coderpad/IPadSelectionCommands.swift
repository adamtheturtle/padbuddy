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
        @FocusedValue(\.focusedPadAccountID) private var padAccountID
        @FocusedValue(\.focusedPadFavoriteState) private var favoriteState
        @FocusedValue(\.isReadOnly) private var isReadOnly
        @FocusedValue(\.padHasSavableCode) private var padHasSavableCode
        @FocusedValue(\.padSortSelection) private var sortSelection
        @State private var accounts = AccountsStore.shared

        private var isEnded: Bool {
            guard let pad else { return false }

            return pad.isEnded
        }

        private var isFavorite: Bool? {
            guard let pad else { return nil }

            return favoriteState?.value(for: pad.id, accountID: padAccountID)
        }

        private var browserURL: URL? {
            guard let pad else { return nil }

            if let url = pad.webURL {
                return url
            }
            guard let padAccountID,
                  let account = accounts.accounts.first(where: { $0.id == padAccountID }) else { return nil }

            return pad.webURL(fallbackBase: account.resolvedBaseURL)
        }

        var body: some Commands {
            CommandMenu("Pad") {
                Button("Open Pad in Browser") {
                    guard let url = browserURL else { return }

                    BrowserSettings.openExternally(url)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(browserURL == nil)

                Button("Watch Playback") {
                    guard let pad else { return }

                    AppNavigation.shared.watchPlaybackPadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("y", modifiers: [.command])
                .disabled(pad?.playbackURL == nil)

                Divider()

                Button("Edit Pad…") {
                    guard let pad else { return }

                    AppNavigation.shared.editPadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(pad == nil || isReadOnly == true)

                Button(isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                    guard let pad else { return }

                    AppNavigation.shared.toggleFavoritePadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(pad == nil || isFavorite == nil)

                if let sortSelection {
                    Menu("Sort By") {
                        PadSortMenuContent(sort: sortSelection)
                    }
                } else {
                    Button("Sort By") {}
                        .disabled(true)
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
                    guard let pad, let browserURL else { return }

                    let title = pad.title.isEmpty ? pad.id : pad.title
                    Clipboard.copy(markdownLink(title: title, url: browserURL))
                }
                .disabled(pad == nil || browserURL == nil)

                if let url = browserURL {
                    ShareLink("Share Pad…", item: url)
                } else {
                    Button("Share Pad…") {}.disabled(true)
                }

                Divider()

                Button("Save All Code…") {
                    guard let pad else { return }

                    AppNavigation.shared.saveCodePadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(pad == nil || padHasSavableCode != true)

                Divider()

                Button("End Interview…") {
                    guard let pad else { return }

                    AppNavigation.shared.endPadID = .init(id: pad.id, account: padAccountID)
                }
                .disabled(pad == nil || isEnded || isReadOnly == true)

                Button("Delete Pad…") {
                    guard let pad else { return }

                    AppNavigation.shared.deletePadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(pad == nil || isReadOnly == true)
            }
        }
    }

    struct QuestionCommands: Commands {
        @FocusedValue(\.focusedQuestion) private var question
        @FocusedValue(\.focusedQuestionAccountID) private var questionAccountID
        @FocusedValue(\.focusedQuestionFavoriteState) private var favoriteState
        @FocusedValue(\.focusedQuestionLink) private var questionLink
        @FocusedValue(\.isReadOnly) private var isReadOnly
        @FocusedValue(\.questionSortSelection) private var sortSelection

        private var isFavorite: Bool? {
            guard let question else { return nil }

            return favoriteState?.value(for: question.id, accountID: questionAccountID)
        }

        private var questionURL: URL? {
            guard let question else { return nil }

            return questionLink?.value(for: question.id, accountID: questionAccountID)
        }

        var body: some Commands {
            CommandMenu("Question") {
                Button("Open Question in Browser") {
                    guard let questionURL else { return }

                    BrowserSettings.openExternally(questionURL)
                }
                .disabled(questionURL == nil)

                Button("New Pad from Question") {
                    guard let question else { return }

                    AppNavigation.shared.createPadForQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(question == nil || isReadOnly == true)

                Divider()

                Button("Edit Question…") {
                    guard let question else { return }

                    AppNavigation.shared.editQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(question == nil || isReadOnly == true)

                Button(isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                    guard let question else { return }

                    AppNavigation.shared.toggleFavoriteQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(question == nil || isFavorite == nil)

                if let sortSelection {
                    Menu("Sort By") {
                        QuestionSortMenuContent(sort: sortSelection)
                    }
                } else {
                    Button("Sort By") {}
                        .disabled(true)
                }

                Divider()

                Button("Copy Question ID") {
                    guard let question else { return }

                    Clipboard.copy(String(question.id))
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
                .disabled(question == nil)

                Button("Copy Question URL") {
                    guard let questionURL else { return }

                    Clipboard.copy(questionURL.absoluteString)
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
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

                    AppNavigation.shared.deleteQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
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
                .keyboardShortcut(.return, modifiers: [.command, .shift])
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
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(testAction == nil || isReadOnly == true)
            }
        }
    }
#endif
