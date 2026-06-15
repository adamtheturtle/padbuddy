//
//  PadDetailView+Sections.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                propertiesCard
                if hasTimestamps {
                    metaCards
                }
                if !pad.participants.isEmpty {
                    participantsCard
                }
                // One code card per environment. A pad can carry several
                // environments (e.g. a candidate and reference solution, or
                // multiple languages); showing only the active one silently hid
                // the rest. Each card is identified by its language chip and
                // flags the active one, so no separate environments list is
                // needed to tell them apart.
                ForEach(environments) { env in
                    let files = displayFiles(for: env)
                    if !files.isEmpty {
                        EnvironmentCodeCard(
                            files: files,
                            isActive: env.id == pad.activeEnvironmentID,
                            showActiveBadge: environments.count > 1,
                            language: env.language,
                            exampleQuestionID: env.exampleQuestionID,
                            padID: pad.id,
                            dark: colorScheme == .dark
                        )
                    }
                }
                if whiteboardURL != nil {
                    whiteboardCard
                }
                eventsCard
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.top, Spacing.paneV)
            .padding(.bottom, Spacing.paneV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Actions now live in the window toolbar, so the header only carries
            // identity, the metadata chips, and the raw ID below.
            identity
            // A flow layout instead of an HStack so the badges wrap onto a new
            // row when the detail pane is too narrow to fit them side by side. A
            // plain HStack let the row overflow the pane, clipping the rightmost
            // badge at the edge.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                StateBadge(state: pad.status)
                // Skip the pad-level language label when a single code card is
                // shown — that card names the language itself, so repeating it
                // here is redundant. Keep it when there's no card (nothing else
                // names the language) or several (this summarizes the active one).
                if let language = pad.language, !language.isEmpty, codeCardCount != 1 {
                    MetaLabel(text: language.languageDisplayName)
                }
                if let type = pad.interviewType {
                    type.chip
                }
                if pad.isPrivate == true {
                    MetaLabel(text: "Private", systemImage: "lock")
                }
                if let exec = pad.executionEnabled, exec {
                    MetaLabel(text: "Execution enabled", systemImage: "play.circle")
                }
                if let team = pad.team {
                    MetaLabel(text: team.name, systemImage: "person.3")
                }
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The title is edited in place: it reads as the heading until you
            // hover or click in, and commits on Return or when focus leaves.
            InlineEditableTitle(text: $titleDraft, placeholder: "Untitled Pad",
                                focus: $titleFocused) { Task { await commitTitle() } }
            // The owner's name links to their pads (the app's person
            // navigation); the email keeps its mailto below. When the name
            // isn't known the link falls back to showing the email itself.
            if let name = directory.name(for: pad.ownerEmail), !name.isEmpty {
                OwnerPadsLink(email: pad.ownerEmail).font(.callout)
                EmailLink(email: pad.ownerEmail).font(.caption).foregroundStyle(.secondary)
            } else {
                OwnerPadsLink(email: pad.ownerEmail)
            }
        }
    }

    /// Whether the pad carries any of the timestamps the Details section shows, so an
    /// empty section (a bare header) is never rendered.
    private var hasTimestamps: Bool {
        pad.createdAt != nil || pad.informativeUpdatedAt != nil || pad.endedAt != nil
    }

    /// The pad's routine bookkeeping dates, as a native grouped section of labeled
    /// rows rather than free-floating tinted tiles.
    private var metaCards: some View {
        DetailSection(title: "Details", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                if let createdAt = pad.createdAt {
                    LabeledRow(label: "Created", value: createdAt.formatted(date: .long, time: .shortened))
                }
                if let updatedAt = pad.informativeUpdatedAt {
                    LabeledRow(label: "Updated", value: updatedAt.formatted(date: .long, time: .shortened))
                }
                if let endedAt = pad.endedAt {
                    LabeledRow(label: "Ended", value: endedAt.formatted(date: .long, time: .shortened))
                }
            }
        }
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
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Whiteboard", systemImage: "scribble.variable")
                if let url = whiteboardURL {
                    Button {
                        openExternalOrInApp(url)
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ZStack {
                                    Color.subtleStroke
                                    ProgressView().controlSize(.small)
                                }
                                .frame(height: 180)
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .failure:
                                ZStack {
                                    Color.subtleStroke
                                    Label("Couldn’t load whiteboard", systemImage: "photo")
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                }
                                .frame(height: 120)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    /// Open a URL the same way the pad and playback links do: in the default
    /// browser or the in-pane web view, per the user's preference.
    private func openExternalOrInApp(_ url: URL) {
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            browserURL = url
        }
    }

    private var eventsCard: some View {
        DetailSection(title: "Events", systemImage: "list.bullet.rectangle") {
            if isLoading {
                ProgressView().controlSize(.small)
            }
        } content: {
            if let loadError {
                Label(loadError.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if events.isEmpty, !isLoading {
                Text("No events yet.").foregroundStyle(.secondary).font(.callout)
            } else {
                eventList
            }
        }
    }

    private var eventList: some View {
        // Lazy so only the visible timeline rows are built: an active session can
        // emit hundreds of grouped events, each a non-trivial row (icon, chips,
        // actor, timestamp), and this sits inside the detail pane's ScrollView.
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(groupedEvents) { group in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: group.representative.kind))
                        .foregroundStyle(color(for: group.representative.kind))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(displayKind(group.representative.kind))
                                .font(.callout.weight(.semibold))
                            // Event-specific context from `metadata` — e.g. the language
                            // for a run, the question id, or a spectator join — kept as
                            // restrained secondary text to match the timeline.
                            if let context = eventContext(group.representative) {
                                Text(context)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if group.count > 1 {
                                Chip(text: "×\(group.count)", tint: .accentColor)
                            }
                            if let actor = eventActor(group.representative) {
                                // Emphasize the most recently-active participant so the
                                // eye is drawn to whoever acted last in the session.
                                let isActive = group.representative.userName == activeParticipant
                                eventActorView(actor: actor, isActive: isActive,
                                               email: group.representative.userEmail)
                            }
                        }
                        eventTimestamp(for: group)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: group))
            }
        }
    }

    /// The actor name shown beside an event. Org members resolve to an email, so
    /// their name becomes a link to their pads, mirroring the Participants card.
    /// Everyone else stays plain text using weight (not link-blue) for the active
    /// emphasis, so the color never implies a tap target that isn't there.
    @ViewBuilder
    private func eventActorView(actor: String, isActive: Bool, email: String?) -> some View {
        let weight: Font.Weight = isActive ? .semibold : .regular
        if let memberEmail = memberEmail(forName: actor) {
            Button {
                AppNavigation.shared.showPads(PadsRequest(ownerEmail: memberEmail))
            } label: {
                Text("· \(actor)")
                    .font(.callout.weight(weight))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Show pads from \(actor)")
        } else {
            Text("· \(actor)")
                .font(.callout.weight(weight))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .help(email ?? actor)
        }
    }

    @ViewBuilder
    private func eventTimestamp(for group: PadEventGroup) -> some View {
        if let first = group.representative.createdAt {
            if group.count > 1, let last = group.lastEvent.createdAt {
                let firstText = first.formatted(date: .long, time: .shortened)
                let lastText = last.formatted(date: .omitted, time: .shortened)
                Text("\(firstText) - \(lastText)")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(first.formatted(date: .long, time: .shortened))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// How many environments actually render a code card (i.e. have files to
    /// show). When exactly one does, that card's own language chip names the
    /// language, so the header chip would just repeat it.
    private var codeCardCount: Int {
        environments.count(where: { !displayFiles(for: $0).isEmpty })
    }

    /// The non-empty files of an environment, each paired with a language
    /// inferred from its own extension. A multi-file project (e.g. a Django
    /// app) mixes `.py`, `.html`, and `.css`; deriving the language per file
    /// lets each be highlighted correctly instead of forcing the environment's
    /// single language onto all of them.
    func displayFiles(for env: PadEnvironment) -> [CodeFile] {
        env.fileContents.enumerated().compactMap { index, file in
            guard let body = file.contents, !body.isEmpty else { return nil }
            let stableID = file.path.flatMap { $0.isEmpty ? nil : $0 } ?? "idx-\(index)"
            return CodeFile(
                id: stableID,
                path: file.path,
                contents: body,
                language: CodeFile.language(forPath: file.path, fallback: env.language)
            )
        }
    }

    private var groupedEvents: [PadEventGroup] {
        PadEventGrouping.group(events)
    }

    /// The participant who acted most recently in the session. Events are grouped
    /// oldest-first, so the most recent named actor is found by scanning from the
    /// end. Nil when no event carries a user name.
    private var activeParticipant: String? {
        for group in groupedEvents.reversed() {
            if let name = group.lastEvent.userName ?? group.representative.userName, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Turns a raw event kind (e.g. `added_question`) into human-readable copy
    /// (`Added Question`). The API uses snake_case, so underscores become spaces
    /// before capitalizing rather than surviving into the UI.
    private func displayKind(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// The actor to show for an event: the participant's name, falling back to their
    /// email when the API gives no name (so an email-only actor still appears rather
    /// than vanishing). `nil` when neither is present.
    private func eventActor(_ event: PadEvent) -> String? {
        if let name = event.userName, !name.isEmpty { return name }
        if let email = event.userEmail, !email.isEmpty { return email }
        return nil
    }

    /// A short, human-readable detail drawn from an event's `metadata`, interpreted
    /// by kind: the language for a run ("Ran Python"), the question id for an added
    /// question ("Added Question #123"), or a spectator join ("Joined as spectator").
    /// `nil` when there's no metadata or it isn't one of these recognized shapes.
    private func eventContext(_ event: PadEvent) -> String? {
        guard let meta = event.metadata?.trimmingCharacters(in: .whitespacesAndNewlines),
              !meta.isEmpty else { return nil }
        switch event.kind.lowercased() {
        case "ran", "executed": return meta.languageDisplayName
        case "added_question": return "#\(meta)"
        case "joined" where meta.lowercased() == "spectator": return "as spectator"
        default: return nil
        }
    }

    private func icon(for kind: String) -> String {
        switch kind.lowercased() {
        case "joined": "person.fill.badge.plus"
        case "left": "person.fill.badge.minus"
        case "ended": "flag.checkered"
        case "started": "play.fill"
        case "edited", "typed": "pencil"
        case "ran", "executed": "play.circle"
        default: "circle.fill"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind.lowercased() {
        case "joined": .green
        case "left": .secondary
        case "ended": .gray
        case "started": .blue
        case "ran", "executed": .orange
        default: .accentColor
        }
    }

    private func accessibilityLabel(for group: PadEventGroup) -> String {
        var parts = [displayKind(group.representative.kind)]
        if let context = eventContext(group.representative) { parts.append(context) }
        if group.count > 1 { parts.append("\(group.count) times") }
        if let user = eventActor(group.representative) { parts.append("by \(user)") }
        if let when = group.representative.createdAt {
            parts.append("at \(when.formatted(date: .long, time: .shortened))")
        }
        return parts.joined(separator: " ")
    }
}
