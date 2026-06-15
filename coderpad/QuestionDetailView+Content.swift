//
//  QuestionDetailView+Content.swift
//  coderpad
//

import SwiftUI

extension QuestionDetailView {
    var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                propertiesCard
                metaCards
                // The editable long-form fields (description, candidate
                // instructions, solution) are always shown, even when empty, so
                // they can be filled in place — there's no separate edit window
                // anymore (#333, #335).
                descriptionCard
                instructionsCard
                if !question.testCases.isEmpty {
                    testCasesCard
                }
                if !question.customFiles.isEmpty {
                    filesCard
                }
                starterCodeCards
                solutionCard
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.top, Spacing.paneV)
            .padding(.bottom, Spacing.paneV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The freshly created pad shown in the in-pane browser, mirroring
    /// `PadDetailView` so creating a pad here behaves like opening one there:
    /// inline by default, with buttons to break out to a separate window or
    /// the default browser.
    func padBrowser(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    showBrowser = false
                } label: {
                    Label("Back to Question", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    openWindow(id: "pad-browser", value: url)
                } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .help("Open in separate window")
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in separate window")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .floatingGlass(in: Rectangle(), fallback: .thinMaterial)
            Divider()
            PadBrowserView(url: url)
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Actions now live in the window toolbar, so the header only carries
            // identity and the metadata chips below.
            headerIdentity
            HStack(spacing: 8) {
                if let lang = question.language, !lang.isEmpty {
                    MetaLabel(text: lang.languageDisplayName)
                }
                question.interviewType.chip
                if question.shared == true {
                    MetaLabel(text: "Shared", systemImage: "person.2")
                }
                if question.testCasesEnabled == true {
                    MetaLabel(text: "Test cases", systemImage: "checkmark.seal")
                }
                if question.isDraft == true {
                    Chip(text: "Draft", systemImage: "doc.badge.ellipsis", tint: .orange)
                }
                if question.publicTakeHomeSettingID != nil {
                    // The API exposes only the setting's ID, not the candidate-facing
                    // public take-home URL (that link is created and copied inside
                    // CoderPad's web app and isn't derivable from this ID). So we
                    // surface the fact that a public link is configured, rather than
                    // fabricating a URL that might not resolve.
                    MetaLabel(text: "Public link", systemImage: "globe")
                        .help("This question has a public take-home link configured in CoderPad. "
                            + "Copy the link from CoderPad's web app to share it.")
                        .accessibilityLabel("Public take-home link configured")
                }
            }
        }
    }

    var headerIdentity: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // The title is edited in place: it reads as the heading until you
                // hover or click in, and commits on Return or when focus leaves.
                InlineEditableTitle(text: $titleDraft, placeholder: "Untitled Question",
                                    focus: $titleFocused) { Task { await commitTitle() } }
                if let author = question.authorName {
                    Text("by \(author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // The owner's name links to their pads (the app's person
                // navigation); the email keeps its mailto below. When the name
                // isn't known the link falls back to showing the email itself.
                if let name = directory.name(for: question.ownerEmail), !name.isEmpty {
                    OwnerPadsLink(email: question.ownerEmail)
                        .font(.caption)
                    EmailLink(email: question.ownerEmail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    OwnerPadsLink(email: question.ownerEmail)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    var metaCards: some View {
        // An adaptive grid rather than a fixed HStack: three equal tiles fit on
        // one row in a wide pane, but reflow onto extra rows as it narrows.
        // A plain HStack instead overflows the pane — clipping the trailing tile
        // and hyphenating its label (CRE-ATED / UP-DATED) — once the tiles can't
        // all fit at their minimum width.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                  alignment: .leading, spacing: 12) {
            if let used = question.used {
                StatTile(title: "Times used", value: "\(used)", systemImage: "chart.bar.fill", tint: .blue)
            }
            if let createdAt = question.createdAt {
                StatTile(title: "Created", value: createdAt.formatted(date: .long, time: .omitted),
                         systemImage: "calendar.badge.plus", tint: .teal)
            }
            if let updatedAt = question.updatedAt {
                StatTile(title: "Updated", value: updatedAt.formatted(date: .long, time: .omitted),
                         systemImage: "clock.arrow.circlepath", tint: .orange)
            }
        }
    }

    var instructionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Candidate Instructions", systemImage: "text.book.closed")
                let instructions = question.candidateInstructions
                if instructions.isEmpty {
                    // #333: keep the section visible when there are no instructions
                    // yet, so the first part can be added in place.
                    InlineEditableText(text: "", placeholder: "No candidate instructions yet.",
                                       label: "candidate instructions") { await commitInstruction(at: 0, text: $0) }
                } else {
                    // Each part is edited independently (#334): committing one part
                    // resends the whole list with only that part's text changed.
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 6) {
                            // When a question has several instruction parts, label each so
                            // they read as distinct sections rather than one run-on block.
                            if instructions.count > 1 {
                                Text("Part \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            // Mirror the test-case "Hidden" badge: an instruction the
                            // candidate doesn't see by default is meaningful review context.
                            if !item.defaultVisible {
                                Chip(text: "Hidden by default", systemImage: "eye.slash", tint: .gray)
                            }
                            InlineEditableText(text: item.instructions, placeholder: "Empty",
                                               label: instructions.count > 1 ? "part \(index + 1)" : "candidate instructions") {
                                await commitInstruction(at: index, text: $0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // A hairline between parts, like the Test Cases card, so multiple
                        // instructions are visually separated instead of blurring together.
                        if index != instructions.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The question's test cases, shown to an interviewer in full. The candidate
    /// only sees the cases marked `visible`, so hidden ones carry a badge to make
    /// that distinction clear when reviewing.
    var testCasesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Test Cases", systemImage: "checkmark.seal")
                ForEach(question.testCases) { testCase in
                    testCaseRow(testCase)
                    if testCase.id != question.testCases.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func testCaseRow(_ testCase: QuestionTestCase) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                testCaseLine(label: "Input", value: argumentsDisplay(testCase.arguments))
                testCaseLine(label: "Expected", value: testCase.returnValue ?? "—")
            }
            Spacer(minLength: 8)
            if testCase.visible == false {
                Chip(text: "Hidden", systemImage: "eye.slash", tint: .gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func testCaseLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The API returns each argument as its own already-formatted string (e.g. a
    /// quoted string or a JSON literal), so join them into a call-style list.
    func argumentsDisplay(_ arguments: [String]?) -> String {
        guard let arguments, !arguments.isEmpty else { return "—" }
        return arguments.joined(separator: ", ")
    }

    /// The question's attached custom files. The API exposes only metadata (name,
    /// description, size) for these, not their contents, so this is a manifest of
    /// what's bundled rather than a viewer.
    var filesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Files", systemImage: "doc.on.doc")
                ForEach(Array(question.customFiles.enumerated()), id: \.offset) { index, file in
                    fileRow(file)
                    if index != question.customFiles.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func fileRow(_ file: QuestionCustomFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(file))
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
                if let description = file.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let size = file.filesize, !size.isEmpty {
                Text(size)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A display name for a custom file: its filename, falling back to its title,
    /// then a generic placeholder when the API supplies neither.
    func fileName(_ file: QuestionCustomFile) -> String {
        if let filename = file.filename, !filename.isEmpty { return filename }
        if let title = file.title, !title.isEmpty { return title }
        return "Untitled file"
    }

    /// The starter code a candidate begins from when this question is used (the
    /// API's `contents`), plus the test-cases variant when it's present and
    /// meaningfully different. Already in hand from the question fetch — no extra
    /// call — and hidden when absent.
    @ViewBuilder
    var starterCodeCards: some View {
        if let contents = question.contents, !contents.isEmpty {
            starterCodeCard(title: "Starter Code", code: contents)
        }
        if let testContents = question.contentsForTestCases, !testContents.isEmpty,
           testContents != question.contents {
            starterCodeCard(title: "Starter Code (Test Cases)", code: testContents)
        }
    }

    func starterCodeCard(title: String, code: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, systemImage: "chevron.left.slash.chevron.right")
                HighlightedCode(contents: code, language: question.language, dark: colorScheme == .dark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The question's description, edited in place. Always shown (empty or not) so
    /// a missing description can be added without a separate editor (#333, #335).
    var descriptionCard: some View {
        editableLongFormCard(title: "Description", text: question.description ?? "",
                             placeholder: "No description yet.", label: "description") {
            await commitDescription($0)
        }
    }

    /// The question's solution, edited in place, always shown like the description.
    var solutionCard: some View {
        editableLongFormCard(title: "Solution", text: question.solution ?? "",
                             placeholder: "No solution yet.", label: "solution") {
            await commitSolution($0)
        }
    }

    /// A card pairing a section header with an inline-editable long-form field.
    /// `onSave` returns `true` once the edit is committed so the editor can close.
    func editableLongFormCard(title: String, text: String, placeholder: String, label: String,
                              onSave: @escaping (String) async -> Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, systemImage: "doc.text")
                InlineEditableText(text: text, placeholder: placeholder, label: label, onSave: onSave)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A long-form field that reads as rendered Markdown until you click its hover
/// pencil, when it becomes a text editor with Save / Cancel. Each commit sends a
/// single-field `PUT` for the question (see `QuestionDetailView` commits), so the
/// description, each candidate-instruction part, and the solution are all edited in
/// place rather than in a separate window (#335). Empty fields still render (showing
/// `placeholder`) so they can be filled in (#333).
struct InlineEditableText: View {
    let text: String
    var placeholder: String
    /// Human-readable name of this field, used for the pencil's help/accessibility
    /// label (e.g. "description", "part 2").
    var label: String
    /// Commits the edited text, returning `true` on success so the editor closes.
    let onSave: (String) async -> Bool

    /// While offline the app is read-only, so long-form fields aren't editable (#321).
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing { editor } else { display }
        }
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    private var display: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    MarkdownText(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isReadOnly {
                Button { beginEditing() } label: {
                    Image(systemName: "pencil")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovered ? 1 : 0)
                .help("Edit \(label)")
                .accessibilityLabel("Edit \(label)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.callout)
                .frame(minHeight: 90)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.subtleStroke, lineWidth: 1))
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { cancel() }
                    .disabled(saving)
                Button { Task { await commit() } } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
        }
    }

    private func beginEditing() {
        draft = text
        editing = true
        focused = true
    }

    private func cancel() {
        editing = false
        focused = false
    }

    private func commit() async {
        saving = true
        let saved = await onSave(draft)
        saving = false
        // On failure the detail view surfaces the error in its alert; keep the
        // editor open so the unsaved text isn't lost.
        if saved {
            editing = false
            focused = false
        }
    }
}
