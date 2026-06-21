//
//  TemplateCommands.swift
//  coderpad
//
//  File-menu commands for interview templates (#525). Saving and managing are static menu
//  items here; running a template (create + open a pad) happens from the Cmd-K command
//  palette and the management sheet's "Use" button, which read the live template list and
//  so don't need a dynamically-rebuilt menu.
//

import SwiftUI

struct TemplateCommands: Commands {
    /// The question selected in the frontmost window, so "Save Question as Template…"
    /// seeds from it (and disables when no question is focused).
    @FocusedValue(\.focusedQuestion) private var question

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Save Question as Template…") {
                guard let question else { return }

                AppRouter.requestSaveQuestionAsTemplate(
                    TemplateSeed(
                        questionID: question.id,
                        name: question.displayTitle,
                        language: question.language ?? "python3"
                    )
                )
            }
            .disabled(question == nil)

            Button("Manage Templates…") {
                AppRouter.requestManageTemplates()
            }
        }
    }
}
