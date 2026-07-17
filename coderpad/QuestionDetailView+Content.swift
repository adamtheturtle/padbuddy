//
//  QuestionDetailView+Content.swift
//  coderpad
//

import SwiftUI

extension QuestionDetailView {
    var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                Divider()
                contentModePicker
                selectedPaneContent
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.top, Spacing.paneV)
            .padding(.bottom, Spacing.paneV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var contentModePicker: some View {
        HStack(spacing: 4) {
            ForEach(QuestionDetailPane.allCases) { pane in
                contentModeButton(for: pane)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question detail section")
    }

    private func contentModeButton(for pane: QuestionDetailPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedPane = pane
            }
        } label: {
            Label {
                Text(pane.label)
                    .lineLimit(1)
            } icon: {
                Image(systemName: pane.systemImage)
            }
            .font(.callout.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.24)) : .regular.interactive(),
                     in: .rect(cornerRadius: 12))
        .accessibilityLabel(pane.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    var selectedPaneContent: some View {
        switch selectedPane {
        case .prompt:
            promptPane
        case .materials:
            materialsPane
        case .solution:
            solutionCard
        }
    }

    var promptPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The editable prompt fields are always shown, even when empty, so
            // they can be filled in place — there's no separate edit window
            // anymore (#333, #335).
            descriptionCard
            instructionsCard
        }
    }

    @ViewBuilder
    var materialsPane: some View {
        if hasMaterials {
            VStack(alignment: .leading, spacing: 18) {
                if !question.testCases.isEmpty {
                    testCasesCard
                }
                if !question.customFiles.isEmpty {
                    filesCard
                }
                starterCodeCards
            }
        } else {
            Card {
                ContentUnavailableView("No code, tests, or files", systemImage: "tray")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    var hasMaterials: Bool {
        !question.testCases.isEmpty
            || !question.customFiles.isEmpty
            || (question.contents?.isEmpty == false)
            || (question.contentsForTestCases?.isEmpty == false && question.contentsForTestCases != question.contents)
    }

    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    summaryGroup(title: "Properties", systemImage: "slider.horizontal.3") {
                        propertiesRows
                    }
                    if hasMeta {
                        summaryGroup(title: "Activity", systemImage: "clock") {
                            metaRows
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    summaryGroup(title: "Properties", systemImage: "slider.horizontal.3") {
                        propertiesRows
                    }
                    if hasMeta {
                        Divider()
                        summaryGroup(title: "Activity", systemImage: "clock") {
                            metaRows
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Actions now live in the window toolbar, so the header only carries
            // identity and the metadata chips below.
            headerIdentity
            headerChips
        }
    }

    var headerChips: some View {
        // Match pad detail's wrapping header badges so several question chips
        // reflow cleanly in a narrow detail pane instead of clipping at the edge.
        FlowLayout(spacing: 6, lineSpacing: 6) {
            headerChipContent
        }
    }

    @ViewBuilder
    var headerChipContent: some View {
        if let lang = question.language, !lang.isEmpty {
            MetaLabel(text: lang.coderPadLanguageDisplayName)
        }
        question.interviewType.chip
        if question.shared == true {
            MetaLabel(text: String(localized: "Shared"), systemImage: "person.2")
        }
        if question.testCasesEnabled == true {
            MetaLabel(text: String(localized: "Test cases"), systemImage: "checkmark.seal")
        }
        if question.isDraft == true {
            Chip(text: String(localized: "Draft"), systemImage: "doc.badge.ellipsis", tint: .orange)
        }
        if question.publicTakeHomeSettingID != nil {
            // The API exposes only the setting's ID, not the candidate-facing
            // public take-home URL (that link is created and copied inside
            // CoderPad's web app and isn't derivable from this ID). So we
            // surface the fact that a public link is configured, rather than
            // fabricating a URL that might not resolve.
            MetaLabel(text: String(localized: "Public link"), systemImage: "globe")
                .help("This question has a public take-home link configured in CoderPad. "
                    + "Copy the link from CoderPad's web app to share it.")
                .accessibilityLabel("Public take-home link configured")
        }
    }

    var headerIdentity: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // The title is edited in place: it reads as the heading until you
                // hover or click in, and commits on Return or when focus leaves. The
                // control is self-owning (it holds its own draft and focus), so it takes
                // the question's title and an async commit returning whether it saved.
                InlineEditableTitle(title: question.title, placeholder: "Untitled Question",
                                    isEditable: !isReadOnly,
                                    font: .title.bold()) { newTitle in await commitTitle(newTitle) }
                // Keep the question identity to one owner line under the title. When
                // the org directory has not resolved the name, avoid exposing the raw
                // email in the header and use the generic fallback label.
                if let name = directory.name(for: question.ownerEmail), !name.isEmpty {
                    OwnerName(email: question.ownerEmail)
                        .font(.caption)
                } else {
                    OwnerName(email: question.ownerEmail, fallbackLabel: String(localized: "Owner"))
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Whether the question carries any of the facts the Details section shows, so an
    /// empty section (a bare header) is never rendered.
    var hasMeta: Bool {
        question.used != nil || question.createdAt != nil || question.updatedAt != nil
    }

    /// The question's usage count and bookkeeping dates, as a compact native grouped
    /// section of labeled rows — matching the pad detail's "Details" section rather
    /// than the tall, free-floating tinted tiles this used to be (#332).
    var metaCards: some View {
        DetailSection(title: "Details", systemImage: "info.circle") {
            metaRows
        }
    }

    var metaRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let used = question.used {
                LabeledRow(label: "Times used", value: "\(used)")
            }
            if let createdAt = question.createdAt {
                LabeledRow(label: "Created", value: createdAt.formatted(date: .long, time: .omitted))
            }
            if let updatedAt = question.updatedAt {
                LabeledRow(label: "Updated", value: updatedAt.formatted(date: .long, time: .omitted))
            }
        }
    }

    func summaryGroup(title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var instructionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Candidate Instructions", systemImage: "text.book.closed")
                let instructions = question.candidateInstructions
                if instructions.isEmpty {
                    // #333: keep the section visible when there are no instructions
                    // yet, so the first part can be added in place.
                    InlineEditableText(text: "", placeholder: "Empty",
                                       label: "candidate instructions") { await commitInstruction(at: 0, text: $0) }
                } else {
                    // Each part is edited independently (#334): committing one part
                    // resends the whole list with only that part's text changed.
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, item in
                        instructionPartRow(index: index, item: item, total: instructions.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One candidate-instruction part. Extracted from `instructionsCard` so neither
    /// view's getter type-checks the whole nested ForEach at once and trips the
    /// 250ms budget (warnings-as-errors makes an overrun fatal).
    @ViewBuilder
    private func instructionPartRow(index: Int, item: CandidateInstruction, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // When a question has several instruction parts, label each so
            // they read as distinct sections rather than one run-on block.
            if total > 1 {
                Text("Part \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            // Mirror the test-case "Hidden" badge: an instruction the
            // candidate doesn't see by default is meaningful review context.
            if !item.defaultVisible {
                Chip(text: String(localized: "Hidden by default"),
                     systemImage: "eye.slash", tint: .gray)
            }
            InlineEditableText(
                text: item.instructions, placeholder: "Empty",
                label: total > 1 ? "part \(index + 1)" : "candidate instructions"
            ) {
                await commitInstruction(at: index, text: $0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A hairline between parts, like the Test Cases card, so multiple
        // instructions are visually separated instead of blurring together.
        if index != total - 1 {
            Divider()
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
                testCaseLine(label: "Expected", value: testCase.returnValue ?? String(localized: "None"))
            }
            Spacer(minLength: 8)
            if testCase.visible == false {
                Chip(text: String(localized: "Hidden"), systemImage: "eye.slash", tint: .gray)
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
        guard let arguments, !arguments.isEmpty else { return String(localized: "None") }

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
        return String(localized: "Untitled file")
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

    func starterCodeCard(title: LocalizedStringKey, code: String) -> some View {
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
                             placeholder: "Empty", label: "description") {
            await commitDescription($0)
        }
    }

    /// The question's solution, edited in place, always shown like the description.
    var solutionCard: some View {
        editableLongFormCard(title: "Solution", text: question.solution ?? "",
                             placeholder: "Empty", label: "solution") {
            await commitSolution($0)
        }
    }

    /// A card pairing a section header with an inline-editable long-form field.
    /// `onSave` returns `true` once the edit is committed so the editor can close.
    func editableLongFormCard(title: LocalizedStringKey, text: String, placeholder: LocalizedStringKey, label: String,
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
