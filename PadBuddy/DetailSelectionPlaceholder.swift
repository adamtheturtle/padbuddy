//
//  DetailSelectionPlaceholder.swift
//  coderpad
//

import SwiftUI

/// A useful resting state for list-backed detail columns. The previous bare
/// `ContentUnavailableView` named the missing selection, but left most of the
/// window unexplained. This version previews what the detail contains and gives
/// keyboard/touch users a concrete next step without pretending the pane is an
/// error state.
struct DetailSelectionPlaceholder: View {
    let kind: Kind

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Kind {
        case pad
        case question
        case campaign

        var title: LocalizedStringKey {
            switch self {
            case .pad: "Select a pad"
            case .question: "Select a question"
            case .campaign: "Select a campaign"
            }
        }

        var description: LocalizedStringKey {
            switch self {
            case .pad: "Choose a pad from the list to review its interview details and work."
            case .question: "Choose a question from the list to review its prompt and setup."
            case .campaign: "Choose a campaign from the list to see its candidate test sessions."
            }
        }

        var systemImage: String {
            switch self {
            case .pad: "doc.text"
            case .question: "questionmark.bubble"
            case .campaign: "person.crop.rectangle.stack"
            }
        }

        var accent: Color {
            switch self {
            case .pad: .blue
            case .question: .purple
            case .campaign: .indigo
            }
        }

        var features: [(LocalizedStringKey, String)] {
            switch self {
            case .pad:
                [("Overview", "info.circle"), ("Notes", "note.text"),
                 ("Code", "chevron.left.forwardslash.chevron.right")]

            case .question:
                [("Prompt", "text.alignleft"), ("Starter code", "chevron.left.forwardslash.chevron.right"),
                 ("Test cases", "checklist")]

            case .campaign:
                [("Candidates", "person.2"), ("Progress", "chart.bar"), ("Reports", "doc.text.magnifyingglass")]
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                card
                    .padding(32)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(kind.accent.opacity(0.018))
        .accessibilityIdentifier("detail-selection-placeholder")
    }

    private var card: some View {
        VStack(spacing: 20) {
            icon
            VStack(spacing: 8) {
                Text(kind.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(kind.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 430)
            }
            featureSummary
            selectionHint
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 20 : 40)
        .padding(.vertical, 36)
        .frame(maxWidth: 560)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.06), radius: 24, y: 10)
    }

    private var icon: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 32, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(kind.accent)
            .frame(width: 76, height: 76)
            .background(kind.accent.opacity(0.12), in: Circle())
            .overlay {
                Circle().strokeBorder(kind.accent.opacity(0.18))
            }
            .accessibilityHidden(true)
    }

    private var featureSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { featureLabels }
            VStack(alignment: .leading, spacing: 10) { featureLabels }
        }
        .accessibilityElement(children: .combine)
    }

    private var featureLabels: some View {
        ForEach(Array(kind.features.enumerated()), id: \.offset) { _, feature in
            Label(feature.0, systemImage: feature.1)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.08), in: Capsule())
        }
    }

    private var selectionHint: some View {
        Group {
            #if os(macOS)
                Label("Use the arrow keys to choose from the list", systemImage: "arrow.up.arrow.down")
            #else
                Label("Tap a row in the list to continue", systemImage: "hand.tap")
            #endif
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private var cardBackground: AnyShapeStyle {
        if reduceTransparency {
            #if os(macOS)
                AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            #else
                AnyShapeStyle(Color(uiColor: .systemBackground))
            #endif
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }
}

#Preview("Pad selection") {
    DetailSelectionPlaceholder(kind: .pad)
        .frame(width: 720, height: 620)
}
