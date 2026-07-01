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
                // The interviewer's own rating / notes / tags for this pad (#591),
                // stored locally per pad. Keyed by id so it reloads as the detail
                // pane shows different pads.
                PadEvaluationCard(padID: pad.id)
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
                            dark: colorScheme == .dark,
                            exampleQuestionID: env.exampleQuestionID
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
                        // Downsampled + cached so a large whiteboard isn't decoded
                        // at full resolution, and isn't re-fetched every time this
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

    /// Open a URL the same way the pad and playback links do: in the default
    /// browser or the in-pane web view, per the user's preference.
    private func openExternalOrInApp(_ url: URL) {
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            browserURL = url
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
}
