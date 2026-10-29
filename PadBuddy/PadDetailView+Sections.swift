// swiftlint:disable file_length
//
//  PadDetailView+Sections.swift
//  coderpad
//

import SwiftUI

/// File-scope and nonisolated (mirroring `QuestionDetailPane`): nested in the
/// view, its members inherited MainActor isolation, which the nonisolated
/// pane's content, the way question detail always shows its summary card.
nonisolated enum PadDetailSection: String, CaseIterable, DetailChipItem {
    case overview
    case notes
    case code
    case whiteboard
    case history
    case events
    case analytics

    var id: Self {
        self
    }

    var label: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .notes: "Notes"
        case .code: "Code"
        case .whiteboard: "Whiteboard"
        case .history: "History"
        case .events: "Events"
        case .analytics: "Interview Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .notes: "note.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .whiteboard: "scribble.variable"
        case .history: "clock.arrow.circlepath"
        case .events: "list.bullet.rectangle"
        case .analytics: "chart.bar.doc.horizontal"
        }
    }
}

extension PadDetailView {
    var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: detailSectionSpacing) {
                header
                Divider()
                selectedSectionContent
            }
            .padding(.horizontal, detailHorizontalPadding)
            .padding(.top, detailTopPadding)
            .padding(.bottom, detailBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            sectionSwitcher
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesSpatialDetailBottomInset {
                Color.clear.frame(height: 96)
            }
        }
    }

    private var availableSections: [PadDetailSection] {
        PadDetailSection.allCases.filter { section in
            switch section {
            case .overview, .notes, .events, .analytics:
                true
            case .code:
                // The pad payload already tells us whether environments are due.
                // Use that on the first frame instead of waiting for the separate
                // environment requests, which made the Code chip pop into the bar
                // a moment after the rest of the detail UI (#2881). Once loading
                // finishes, keep the chip only when an environment has displayable
                // files, preserving the existing empty-pad behaviour.
                codeCardCount > 0 || (isLoading && pad.padEnvironmentIDs.contains(where: { $0 > 0 }))
            case .whiteboard:
                whiteboardURL != nil
            case .history:
                hasHistory
            }
        }
    }

    /// The section actually shown: falls back to Notes (always available) when
    /// the selected chip disappears, e.g. a reload drops the pad's only code
    /// environment while Code is selected.
    private var activeSection: PadDetailSection {
        availableSections.contains(selectedSection) ? selectedSection : .overview
    }

    /// Shares question detail's pinned chip bar; the chips bind `selection` and
    /// switch mutually exclusive panes (#980), so a pad's properties, long code,
    /// history, and event timeline no longer stack into one endless scroll.
    private var sectionSwitcher: some View {
        DetailChipBar(items: availableSections,
                      selection: activeSection,
                      horizontalPadding: detailHorizontalPadding,
                      accessibilityLabel: "Pad detail sections") { section in
            withAnimation(.snappy(duration: 0.18)) {
                selectedSection = section
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch activeSection {
        case .overview:
            overviewCard
        case .notes:
            notesCard
        case .code:
            codeCards
        case .whiteboard:
            whiteboardCard
        case .history:
            historyCard
        case .events:
            eventsCard
        case .analytics:
            PadAnalyticsView(client: client, identity: detailLoadIdentity)
        }
    }

    private var codeCards: some View {
        VStack(alignment: .leading, spacing: detailSectionSpacing) {
            if !failedEnvironmentIDs.isEmpty || environmentListWasTruncated {
                incompleteCodeWarning
            }
            ForEach(environments.filter { !displayFiles(for: $0).isEmpty }) { env in
                EnvironmentCodeCard(
                    files: displayFiles(for: env),
                    isActive: env.id == pad.activeEnvironmentID,
                    showActiveBadge: environments.count > 1,
                    language: env.language,
                    padID: pad.id,
                    dark: colorScheme == .dark,
                    exampleQuestionID: env.exampleQuestionID
                )
            }
        }
    }

    private var detailSectionSpacing: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 14 : 18
        #else
            18
        #endif
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
        #if os(visionOS)
            Spacing.paneV + 96
        #else
            #if os(iOS)
                horizontalSizeClass == .compact ? Spacing.paneV + 160 : Spacing.paneV
            #else
                Spacing.paneV
            #endif
        #endif
    }

    private var usesSpatialDetailBottomInset: Bool {
        #if os(visionOS)
            true
        #else
            false
        #endif
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            overviewChips
            overviewSummary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var overviewSummary: some View {
        if hasOverviewSiblings {
            #if os(visionOS)
                LazyVGrid(columns: overviewSpatialColumns, alignment: .leading, spacing: 22) {
                    overviewPropertiesGroup
                    overviewSecondaryGroups
                }
            #else
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) {
                        overviewPropertiesGroup
                            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                        overviewSecondaryGroups
                            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        overviewPropertiesGroup
                        overviewSecondaryGroupsWithDividers
                    }
                }
            #endif
        } else {
            propertyRows
        }
    }

    private var overviewSpatialColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 240), spacing: 34, alignment: .topLeading),
            GridItem(.flexible(minimum: 220), spacing: 0, alignment: .topLeading)
        ]
    }

    private var overviewPropertiesGroup: some View {
        summaryGroup(title: "Properties", systemImage: "slider.horizontal.3") {
            propertyRows
        }
    }

    private var overviewSecondaryGroups: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !pad.participants.isEmpty {
                summaryGroup(title: "Participants", systemImage: "person.2") {
                    participantsContent
                }
            }
            if hasActivity {
                summaryGroup(title: "Activity", systemImage: "clock") {
                    activityRows
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewSecondaryGroupsWithDividers: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !pad.participants.isEmpty {
                Divider()
                summaryGroup(title: "Participants", systemImage: "person.2") {
                    participantsContent
                }
            }
            if hasActivity {
                Divider()
                summaryGroup(title: "Activity", systemImage: "clock") {
                    activityRows
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasOverviewSiblings: Bool {
        !pad.participants.isEmpty || hasActivity
    }

    /// Private interviewer notes are the pad detail's only long-form, user-authored
    /// field. Keep the card visible even when empty so notes can be added in place.
    private var notesCard: some View {
        // The draft key is account-qualified: pad slugs collide across custom
        // servers, and a process-global key by bare slug could restore one
        // organization's unsaved notes into another's pad (#1194).
        InlineEditableText(text: pad.notes ?? "", placeholder: "Empty", label: "Notes",
                           draftKey: "pad/\(owningAccountID?.uuidString ?? "current")/\(pad.id)/notes") {
            await commitNotes($0, basedOn: $1)
        }
    }

    private var header: some View {
        identity
    }

    private var overviewChips: some View {
        // A flow layout instead of an HStack so the badges wrap onto a new row when
        // the detail pane is too narrow to fit them side by side.
        FlowLayout(spacing: 6, lineSpacing: 6) {
            StateBadge(state: pad.status)
            // Skip the pad-level language label when a single code card is shown —
            // that card names the language itself, so repeating it here is redundant.
            // Keep it when there's no card or several (this summarizes the active one).
            if let language = pad.language, !language.isEmpty, codeCardCount != 1 {
                MetaLabel(text: language.coderPadLanguageDisplayName)
            }
            if let type = pad.interviewType {
                type.chip
            }
            if pad.isPrivate == true {
                MetaLabel(text: String(localized: "Private"), systemImage: "lock")
            }
            if let exec = pad.executionEnabled, exec {
                MetaLabel(text: String(localized: "Execution enabled"), systemImage: "play.circle")
            }
            if let team = pad.team {
                MetaLabel(text: team.name, systemImage: "person.3")
            }
        }
    }

    private var hasActivity: Bool {
        pad.createdAt != nil || pad.updatedAt != nil || pad.endedAt != nil
    }

    private var activityRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let createdAt = pad.createdAt {
                padMetadataRow(label: "Created", value: createdAt.formatted(SharedDateStyles.longDateAndTime))
            }
            if let updatedAt = pad.updatedAt {
                padMetadataRow(label: "Updated", value: updatedAt.formatted(SharedDateStyles.longDateAndTime))
            }
            if let endedAt = pad.endedAt {
                padMetadataRow(label: "Ended", value: endedAt.formatted(SharedDateStyles.longDateAndTime))
            }
        }
    }

    func padMetadataRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func summaryGroup(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.76))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var identity: some View {
        // The title is edited in place: it reads as the heading until you
        // hover or click in, and commits on Return or when focus leaves. The
        // control is self-owning (it holds its own draft and focus), so it takes
        // the pad's title and an async commit that returns whether the rename saved.
        CommandEditableTitle(title: pad.title, placeholder: "Untitled Pad",
                             isEditable: !isReadOnly, clampsWidth: !isCompactPhone,
                             font: detailTitleFont, scope: titleEditScope,
                             editRequest: titleEditRequest) { newTitle in
            await commitTitle(newTitle)
        }
    }

    var titleEditScope: CommandTitleEditScope {
        CommandTitleEditScope(accountID: owningAccountID, itemID: pad.id, title: pad.title)
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

    /// The pad's whiteboard drawing, when it has one. Parsed once so the card and
    /// its visibility check agree on whether there's anything to show.
    private var whiteboardURL: URL? {
        guard let drawing = pad.drawing, !drawing.isEmpty else { return nil }

        return URL(string: drawing)
    }

    /// The whiteboard sketch from the interview, rendered inline. Tapping it opens
    /// the full-size image, honouring the same in-app/external preference as the
    /// pad and playback links.
    private var whiteboardCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.contentGroupGap) {
                if let url = whiteboardURL {
                    Button {
                        openExternalOrInApp(url)
                    } label: {
                        // at full resolution, and isn't re-fetched every time this
                        // at full resolution, and is not re-fetched every time this
                        // pad's detail view is rebuilt (#375).
                        WhiteboardImage(url: url)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .stroke(Color.subtleStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Open the whiteboard full size")
                    .accessibilityLabel("Open the whiteboard full size")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Open a URL the same way the pad and playback links do: in the user's browser.
    private func openExternalOrInApp(_ url: URL) {
        BrowserSettings.openExternally(url)
    }

    /// How many environments actually render a code card (i.e. have files to
    /// show). When exactly one does, that card's own language chip names the
    /// language, so the header chip would just repeat it.
    private var codeCardCount: Int {
        environments.count(where: { !displayFiles(for: $0).isEmpty })
    }

    var hasHistory: Bool {
        // Make the destination available while its files are being discovered and
        // fetched. Waiting for the first replay to finish made the History chip pop
        // into an otherwise-settled tab bar several seconds after opening a pad
        // (#2906). It still disappears after a completed empty response.
        !histories.isEmpty
            || isLoadingHistory
            || (isLoading && pad.padEnvironmentIDs.contains(where: { $0 > 0 }))
    }

    // `displayFiles(for:)` — the CodeFile normalization feeding these cards —
    // lives in PadDetailView+SaveCodePaths.swift to keep this file within the
    // length lint.
}
