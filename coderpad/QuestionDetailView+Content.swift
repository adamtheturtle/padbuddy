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
                if let description = question.description, !description.isEmpty {
                    descriptionCard(title: "Description", body: description)
                }
                if !question.candidateInstructions.isEmpty {
                    instructionsCard
                }
                if !question.testCases.isEmpty {
                    testCasesCard
                }
                if !question.customFiles.isEmpty {
                    filesCard
                }
                starterCodeCards
                if let solution = question.solution, !solution.isEmpty {
                    descriptionCard(title: "Solution", body: solution)
                }
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
        EditableContentCard(title: "Candidate Instructions", systemImage: "text.book.closed",
                            onEdit: { showEdit = true }) {
            let instructions = question.candidateInstructions
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
                    MarkdownText(item.instructions)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    func descriptionCard(title: String, body: String) -> some View {
        EditableContentCard(title: title, systemImage: "doc.text", onEdit: { showEdit = true }) {
            MarkdownText(body)
                .font(.callout)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
    }
}

/// A read-only content card whose header reveals a pencil on hover that opens the
/// question's content editor. Mirrors the inline title's hover affordance for the
/// long-form fields (description, candidate instructions, solution) that are edited
/// in the focused sheet rather than in place.
struct EditableContentCard<Content: View>: View {
    let title: String
    let systemImage: String
    let onEdit: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovered = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionHeader(title: title, systemImage: systemImage)
                    Spacer(minLength: 0)
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovered ? 1 : 0)
                    .help("Edit the description, instructions, and solution")
                    .accessibilityLabel("Edit content")
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }
}
