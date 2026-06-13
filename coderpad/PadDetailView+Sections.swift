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
                metaCards
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
        HStack(spacing: 12) {
            AvatarCircle(label: directory.display(pad.ownerEmail), diameter: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.title.isEmpty ? "Untitled Pad" : pad.title)
                    .font(.title.bold())
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
    }

    private var metaCards: some View {
        // An adaptive grid instead of a fixed HStack so the tiles wrap onto a
        // new row when the detail pane is too narrow to fit them side by side.
        // A plain HStack can't shrink the date-bearing tiles below their content
        // width, so it overflowed and the rightmost tile was clipped by the pane
        // edge.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
            // The timestamps are routine bookkeeping dates, so they render as
            // compact tiles rather than full-size StatTiles — keeping the visual
            // weight on the pad's identity and code.
            if let createdAt = pad.createdAt {
                timestampTile(title: "Created", value: createdAt.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "calendar.badge.plus", tint: .blue)
            }
            if let updatedAt = pad.informativeUpdatedAt {
                timestampTile(title: "Updated", value: updatedAt.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "clock.arrow.circlepath", tint: .teal)
            }
            if let endedAt = pad.endedAt {
                timestampTile(title: "Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "flag.checkered", tint: .gray)
            }
        }
    }

    /// A condensed timestamp tile: a small caption-sized value and tight padding,
    /// far less prominent than a `StatTile`. Used for the Created/Updated dates so
    /// they stay legible without dominating the detail pane.
    private func timestampTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.subtleStroke, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
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
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Events", systemImage: "list.bullet.rectangle")
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedEvents) { group in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: group.representative.kind))
                        .foregroundStyle(color(for: group.representative.kind))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(displayKind(group.representative.kind))
                                .font(.callout.weight(.semibold))
                            if group.count > 1 {
                                Chip(text: "×\(group.count)", tint: .accentColor)
                            }
                            if let name = group.representative.userName, !name.isEmpty {
                                // Emphasize the most recently-active participant so the
                                // eye is drawn to whoever acted last in the session.
                                let isActive = name == activeParticipant
                                Text("· \(name)")
                                    .font(.callout.weight(isActive ? .semibold : .regular))
                                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
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

    @ViewBuilder
    private func eventTimestamp(for group: PadEventGroup) -> some View {
        if let first = group.representative.createdAt {
            if group.count > 1, let last = group.lastEvent.createdAt {
                let firstText = first.formatted(date: .abbreviated, time: .shortened)
                let lastText = last.formatted(date: .omitted, time: .shortened)
                Text("\(firstText) - \(lastText)")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(first.formatted(date: .abbreviated, time: .shortened))
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
        if group.count > 1 { parts.append("\(group.count) times") }
        if let user = group.representative.userName, !user.isEmpty { parts.append("by \(user)") }
        if let when = group.representative.createdAt {
            parts.append("at \(when.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " ")
    }
}
