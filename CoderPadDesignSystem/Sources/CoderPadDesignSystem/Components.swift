//
//  Components.swift
//  CoderPadDesignSystem
//
//  The small, reusable, domain-free SwiftUI views the app builds its panes from:
//  cards, grouped section headers, labelled rows, stat tiles, chips, avatars, and
//  the shared reload toolbar button. None of these reference app models, so they
//  can be shared with the HackerRank app (#377). App-specific helpers (e.g. an
//  `AvatarCircle(account:)` convenience, the `PadState`-driven `StateBadge`) stay
//  in the app as extensions/types over these primitives.
//

import SwiftUI

/// A rounded, hairline-bordered container with the standard interior padding.
public struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Spacing.card)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.subtleStroke, lineWidth: 1))
    }
}

/// A native-feeling grouped detail section: a section header (with an optional
/// trailing accessory) over its content, separated by a hairline — no card fill or
/// border. Reads like a native grouped list rather than a stack of dashboard cards;
/// ``Card`` is reserved for genuine card affordances (code/whiteboard previews).
public struct DetailSection<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let trailing: Trailing
    let content: Content

    public init(title: LocalizedStringKey, systemImage: String? = nil,
                @ViewBuilder trailing: () -> Trailing,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionHeader(title: title, systemImage: systemImage)
                Spacer(minLength: 0)
                trailing
            }
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension DetailSection where Trailing == EmptyView {
    init(title: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, trailing: { EmptyView() }, content: content)
    }
}

/// An uppercase, tracked section title with an optional decorative SF Symbol, exposed
/// to VoiceOver's heading rotor.
public struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String?

    public init(title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Decorative: the title beside it carries the meaning, so hide it from
            // VoiceOver rather than announce the raw SF Symbol name as a separate
            // element before the heading (#350).
            if let systemImage {
                Image(systemName: systemImage).font(.callout).accessibilityHidden(true)
            }
            // `.textCase(.uppercase)` rather than `String.uppercased()` so the title
            // stays a `LocalizedStringKey` (and thus localizes), with the locale-aware
            // uppercase applied at render time.
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                // Expose the section title to VoiceOver's heading rotor so users can
                // jump between detail sections; SwiftUI doesn't infer this (#349).
                .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(.secondary)
    }
}

/// A label/value row with a fixed-width leading label, for detail metadata.
public struct LabeledRow: View {
    let label: LocalizedStringKey
    let value: String
    var monospaced: Bool = false

    public init(label: LocalizedStringKey, value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            if monospaced {
                Text(value).font(.callout.monospaced())
            } else {
                Text(value).font(.callout)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A small dashboard tile: an uppercase title (with an optional tinted icon) over a
/// prominent value, wrapped in a ``Card``.
public struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor

    public init(title: LocalizedStringKey, value: String, systemImage: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let systemImage {
                        // Decorative: the tile's title/value text already conveys the
                        // stat, so hide the icon from VoiceOver (#350).
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    // `.textCase(.uppercase)` keeps `title` a localizable
                    // `LocalizedStringKey` rather than uppercasing a raw String (#111).
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        // `title` is a LocalizedStringKey, so compose the combined label from Text
        // (which resolves the localization) rather than String interpolation.
        .accessibilityLabel(Text(title) + Text(verbatim: ": \(value)"))
    }
}

/// A small tinted capsule: an optional SF Symbol plus text. Used for the few states
/// that genuinely benefit from colour (e.g. "Draft").
public struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    @Environment(\.colorSchemeContrast) private var contrast

    public init(text: String, systemImage: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2).accessibilityHidden(true)
            }
            Text(text).font(.caption)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(ChipContrast.fill(0.12, contrast)), in: Capsule())
        .foregroundStyle(tint)
        .overlay(Capsule().stroke(tint.opacity(ChipContrast.stroke(0.2, contrast)),
                                  lineWidth: ChipContrast.lineWidth(contrast)))
    }
}

/// A restrained, native-feeling metadata label: an optional SF Symbol plus secondary
/// text, with no coloured capsule — the default treatment for informational status.
public struct MetaLabel: View {
    let text: String
    var systemImage: String?

    public init(text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2).accessibilityHidden(true)
            }
            Text(text).font(.caption)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.secondary)
    }
}

/// A circular avatar showing a name's initials (or an SF Symbol) on a tinted disc.
/// Decorative: always sits beside text naming the same entity, so it's hidden from
/// VoiceOver.
public struct AvatarCircle: View {
    let label: String
    var diameter: CGFloat = 32
    var tint: Color = .accentColor
    /// When set, the avatar shows this SF Symbol (tinted) instead of the initials.
    var symbol: String?

    public init(label: String, diameter: CGFloat = 32, tint: Color = .accentColor, symbol: String? = nil) {
        self.label = label
        self.diameter = diameter
        self.tint = tint
        self.symbol = symbol
    }

    public var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            Circle().stroke(tint.opacity(0.25), lineWidth: 0.5)
            if let symbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.42, weight: .medium))
                    .foregroundStyle(tint)
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: diameter, height: diameter)
        // Decorative throughout: every avatar sits beside text that names the same
        // person or account, so the initials/symbol would only be VoiceOver noise.
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = label
            .replacingOccurrences(of: "@", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map(String.init)
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        let result = letters.joined().uppercased()
        return result.isEmpty ? "?" : result
    }
}

/// The Reload action shared by every section's window toolbar. Kept as a stable
/// `Label` (rather than swapping the whole control for a `ProgressView` while
/// loading) so the toolbar item keeps a fixed size and identity; the spinning
/// feedback comes from a symbol effect on the icon.
public struct ReloadToolbarButton: View {
    let isLoading: Bool
    let action: () -> Void

    public init(isLoading: Bool, action: @escaping () -> Void) {
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label("Reload", systemImage: "arrow.clockwise")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading)
        }
        .help("Reload")
        .disabled(isLoading)
    }
}
