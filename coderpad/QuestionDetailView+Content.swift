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
            .padding(.horizontal, detailHorizontalPadding)
            .padding(.top, detailTopPadding)
            .padding(.bottom, detailBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        #if os(iOS)
            horizontalSizeClass == .compact ? Spacing.paneV + 120 : Spacing.paneV
        #else
            Spacing.paneV
        #endif
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
                // command-aware editor also lets Question > Edit Question open the
                // same rename affordance without duplicating save logic.
                CommandEditableTitle(
                    title: question.title,
                    placeholder: "Untitled Question",
                    isEditable: !isReadOnly,
                    clampsWidth: isCompactPhone,
                    font: detailTitleFont,
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
        VStack(alignment: .leading, spacing: 6) {
            if let author = displayableText(question.authorName) {
                LabeledRow(label: "Author", value: author)
            }
            if let organization = displayableText(question.organizationName) {
                LabeledRow(label: "Organization", value: organization)
            }
            if let used = question.used {
                LabeledRow(label: "Times used", value: "\(used)")
            }
            if !question.testCases.isEmpty {
                LabeledRow(label: "Test cases", value: "\(question.testCases.count)")
            }
            if !question.customFiles.isEmpty {
                LabeledRow(label: "Custom files", value: "\(question.customFiles.count)")
            }
            if let createdAt = question.createdAt {
                LabeledRow(label: "Created", value: createdAt.formatted(date: .long, time: .omitted))
            }
            if let updatedAt = question.updatedAt {
                LabeledRow(label: "Updated", value: updatedAt.formatted(date: .long, time: .omitted))
            }
        }
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
}
