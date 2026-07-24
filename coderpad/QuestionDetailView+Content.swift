//
//  QuestionDetailView+Content.swift
//  coderpad
//

// swiftlint:disable file_length

import SwiftUI

extension QuestionDetailView {
    var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                selectedPaneContent
            }
            .padding(.horizontal, detailHorizontalPadding)
            .padding(.top, detailTopPadding)
            .padding(.bottom, detailBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pinned above the scroll like pad detail's section navigator, so the
        // pane switch stays reachable after scrolling a long prompt instead of
        // scrolling away with the content it used to sit in.
        .safeAreaInset(edge: .top, spacing: 0) {
            paneSwitcher
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isCompactPhone {
                Color.clear.frame(height: 96)
            }
        }
    }

    /// Shares pad detail's pinned chip bar; here the chips bind `selection` and
    /// until explicitly asked for (it shouldn't sit visible during a screen share).
    /// screen until explicitly asked for (the latter shouldn't sit visible during a screen share).
    private var paneSwitcher: some View {
        DetailChipBar(items: QuestionDetailPane.allCases,
                      selection: selectedPane,
                      horizontalPadding: detailHorizontalPadding,
                      accessibilityLabel: "Question detail section") { pane in
            withAnimation(.snappy(duration: 0.18)) {
                selectedPane = pane
            }
        }
    }

    private var detailHorizontalPadding: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 16 : Spacing.paneH
        #else
            Spacing.paneH
        #endif
    }

    private var detailTopPadding: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 10 : Spacing.paneV
        #else
            Spacing.paneV
        #endif
    }

    private var detailBottomPadding: CGFloat {
        Spacing.paneV
    }

    @ViewBuilder
    var selectedPaneContent: some View {
        switch selectedPane {
        case .overview:
            overviewCard
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
            Divider()
            instructionsCard
            if let prompt = displayableAIAssistSystemPrompt {
                Divider()
                aiAssistSystemPromptCard(prompt)
            }
        }
    }

    private var displayableAIAssistSystemPrompt: String? {
        guard let prompt = question.aiAssistCustomSystemPrompt,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return prompt
    }

    private func aiAssistSystemPromptCard(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "AI Assist Custom System Prompt", systemImage: "lock.shield")
            Text("Confidential interviewer-only content. CoderPad appends this after its base AI Assist system prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: prompt)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var materialsPane: some View {
        if hasMaterials {
            VStack(alignment: .leading, spacing: 18) {
                if !question.testCases.isEmpty {
                    testCasesCard
                    if !question.customFiles.isEmpty || question.customDatabase != nil || hasStarterCode {
                        Divider()
                    }
                }
                if !question.customFiles.isEmpty {
                    filesCard
                    if question.customDatabase != nil || hasStarterCode {
                        Divider()
                    }
                }
                if question.customDatabase != nil {
                    customDatabaseCard
                    if hasStarterCode { Divider() }
                }
                starterCodeCards
            }
        } else {
            starterCodeUnavailableView
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// The REST API omits project-template files entirely, so an empty response is
    /// not proof that the question has no starter code (#2892). Say what is known
    /// instead of presenting the API's incomplete representation as authoritative.
    var starterCodeUnavailableView: some View {
        ContentUnavailableView(
            "Starter code unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("Project starter files may exist in CoderPad but are not exposed by the API.")
        )
    }

    var hasMaterials: Bool {
        !question.testCases.isEmpty
            || !question.customFiles.isEmpty
            || question.customDatabase != nil
            || (question.contents?.isEmpty == false)
            || (question.contentsForTestCases?.isEmpty == false && question.contentsForTestCases != question.contents)
    }

    var hasStarterCode: Bool {
        question.contents?.isEmpty == false
            || (question.contentsForTestCases?.isEmpty == false && question.contentsForTestCases != question.contents)
    }

    var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerChips
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    if hasMeta {
                        summaryGroup(title: "Properties", systemImage: "slider.horizontal.3") {
                            propertiesRows
                        }
                        summaryGroup(title: "Activity", systemImage: "clock") {
                            metaRows
                        }
                    } else {
                        propertiesRows
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    if hasMeta {
                        summaryGroup(title: "Properties", systemImage: "slider.horizontal.3") {
                            propertiesRows
                        }
                        Divider()
                        summaryGroup(title: "Activity", systemImage: "clock") {
                            metaRows
                        }
                    } else {
                        propertiesRows
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerIdentity
            QuestionDetailRefreshStatus(state: questionRefresh)
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
                // command-aware editor also lets Question > Edit Question open the
                // same rename affordance without duplicating save logic.
                CommandEditableTitle(
                    title: question.title,
                    placeholder: "Untitled Question",
                    isEditable: !isReadOnly,
                    clampsWidth: isCompactPhone,
                    font: detailTitleFont,
                    scope: titleEditScope,
                    editRequest: titleEditRequest
                ) { newTitle in await commitTitle(newTitle) }
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

    var isCompactPhone: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    private var detailTitleFont: Font {
        isCompactPhone ? .title2.bold() : .title.bold()
    }

    /// Whether the question carries any of the facts the Details section shows, so an
    /// empty section (a bare header) is never rendered.
    var hasMeta: Bool {
        question.used != nil
            || question.createdAt != nil
            || question.updatedAt != nil
            || displayableText(question.authorName) != nil
            || displayableText(question.organizationName) != nil
            || !question.testCases.isEmpty
            || !question.customFiles.isEmpty
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
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            if let author = displayableText(question.authorName) {
                inspectorRow(label: "Author", value: author)
            }
            if let organization = displayableText(question.organizationName) {
                inspectorRow(label: "Organization", value: organization)
            }
            if let used = question.used {
                inspectorRow(label: "Times used", value: "\(used)")
            }
            if !question.testCases.isEmpty {
                inspectorRow(label: "Test cases", value: "\(question.testCases.count)")
            }
            if !question.customFiles.isEmpty {
                inspectorRow(label: "Custom files", value: "\(question.customFiles.count)")
            }
            // The shared style rather than `formatted(date:time:)`, which builds a new
            // `Date.FormatStyle` for each call, on every render of this section (#2238).
            if let createdAt = question.createdAt {
                inspectorRow(label: "Created", value: createdAt.formatted(SharedDateStyles.longDate))
            }
            if let updatedAt = question.updatedAt {
                inspectorRow(label: "Updated", value: updatedAt.formatted(SharedDateStyles.longDate))
            }
        }
    }

    private func inspectorRow(label: LocalizedStringKey, value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func displayableText(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        return text
    }

    func summaryGroup(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, systemImage: systemImage)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Candidate Instructions", systemImage: "text.book.closed")
            let instructions = question.candidateInstructions
            if instructions.isEmpty {
                // #333: keep the section visible when there are no instructions
                // yet, so the first part can be added in place.
                let emptyKey = inlineDraftKey("instructions-0-\(InlineEditDrafts.contentToken(""))")
                InlineEditableText(text: "", placeholder: "Empty",
                                   label: "candidate instructions",
                                   draftKey: emptyKey) {
                    await commitInstruction(at: 0, original: "", text: $0, basedOn: $1)
                }
            } else {
                // Each part is edited independently (#334): committing one part
                // resends the whole list with only that part's text changed.
                // Indices rather than `Array(enumerated())`, which materializes a
                // fresh array of tuples on every render of the card (#2236).
                ForEach(instructions.indices, id: \.self) { index in
                    instructionPartRow(index: index, item: instructions[index], total: instructions.count)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // The key carries a token of the part's mount-time text as well as its
            // index: instruction parts have no server ids, and an index-only key
            // could restore a stashed draft into a different part after a server
            // update inserts or reorders parts while the pane is unmounted (#1798).
            InlineEditableText(
                text: item.instructions, placeholder: "Empty",
                label: total > 1 ? "part \(index + 1)" : "candidate instructions",
                draftKey: inlineDraftKey("instructions-\(index)-\(InlineEditDrafts.contentToken(item.instructions))")
            ) {
                await commitInstruction(at: index, original: item.instructions, text: $0, basedOn: $1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A hairline between parts, like the Test Cases card, so multiple
        // instructions are visually separated instead of blurring together.
        if index != total - 1 {
            Divider()
        }
    }
}
