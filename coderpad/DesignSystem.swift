//
//  DesignSystem.swift
//  coderpad
//

import AppKit
import SwiftUI

extension Color {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleStroke = Color.primary.opacity(0.08)
    /// The neutral capsule fill an *idle* filter chip wears so every chip in the bar
    /// reads as a control rather than bare text + chevron (#352). Matches the
    /// saved-search chips' resting pill; a set filter swaps this for the accent fill.
    static let chipIdleFill = Color.primary.opacity(0.06)

    /// Parses an "#RRGGBB" (or "RRGGBB") hex string into an sRGB color, or `nil` if
    /// it isn't a well-formed six-digit hex value.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }

        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// This color as an "#RRGGBB" sRGB hex string, or `nil` if it can't be resolved
    /// to fixed components (e.g. a dynamic/catalog color).
    var hexString: String? {
        guard let resolved = NSColor(self).usingColorSpace(.sRGB) else { return nil }

        let red = Int((resolved.redComponent * 255).rounded())
        let green = Int((resolved.greenComponent * 255).rounded())
        let blue = Int((resolved.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

/// Shared layout constants so pane chrome stays in sync across detail views.
/// Tweak these here instead of hunting for matching literals in every view.
enum Spacing {
    /// Horizontal inset for pane content.
    static let paneH: CGFloat = 22
    /// Vertical inset for pane content (its top gap below the toolbar and its
    /// bottom padding).
    static let paneV: CGFloat = 22
    /// Interior padding for ``Card``.
    static let card: CGFloat = 16
    /// Horizontal inset for the inline banner.
    static let bannerH: CGFloat = 14
}

/// Contrast-aware opacities for the app's tinted chips and badges. Their default
/// fills are deliberately subtle; under the system "Increase Contrast"
/// accessibility setting they're raised (and the hairline stroke thickened) so
/// the controls stay legible for low-vision users.
enum ChipContrast {
    static func fill(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.2) : base
    }

    static func stroke(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.4) : base
    }

    static func lineWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 1 : 0.5
    }
}

/// A pad's lifecycle state. A live pad is the one status that genuinely benefits
/// from standing out, so it keeps a subtle green capsule; every other state reads
/// as restrained secondary metadata (an SF Symbol + text, see ``MetaLabel``) so the
/// list doesn't fill up with competing coloured pills.
struct StateBadge: View {
    let state: PadState
    /// Under "Increase Contrast" the subtle tinted fill/stroke are strengthened so
    /// the badge stays legible for low-vision users (see ChipContrast).
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if state == .active {
            Text(state.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(ChipContrast.fill(0.16, contrast)), in: Capsule())
                .foregroundStyle(.green)
                .overlay(Capsule().stroke(Color.green.opacity(ChipContrast.stroke(0.25, contrast)),
                                          lineWidth: ChipContrast.lineWidth(contrast)))
        } else {
            MetaLabel(text: state.label, systemImage: state.systemImage)
        }
    }
}

struct AvatarCircle: View {
    let label: String
    var diameter: CGFloat = 32
    var tint: Color = .accentColor
    /// When set, the avatar shows this SF Symbol (tinted) instead of the initials.
    var symbol: String?

    var body: some View {
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

extension AvatarCircle {
    /// Builds the avatar from an account: its chosen symbol and tint when set,
    /// otherwise the name's initials on the account's default tint.
    init(account: Account, diameter: CGFloat = 32) {
        self.init(label: account.name, diameter: diameter,
                  tint: account.avatarTint, symbol: account.iconSymbol)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(Spacing.card)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.subtleStroke, lineWidth: 1))
    }
}

/// A native-feeling grouped detail section: a section header (with an optional
/// trailing accessory) over its content, separated by a hairline — no card fill or
/// border. Used for pad-detail metadata (details, participants, events) so the pane
/// reads like a native grouped list rather than a stack of dashboard cards. ``Card``
/// is reserved for genuine card affordances (code and whiteboard previews).
struct DetailSection<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let trailing: Trailing
    let content: Content

    init(title: LocalizedStringKey, systemImage: String? = nil,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
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

extension DetailSection where Trailing == EmptyView {
    init(title: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, trailing: { EmptyView() }, content: content)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String?

    var body: some View {
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

struct LabeledRow: View {
    let label: LocalizedStringKey
    let value: String
    var monospaced: Bool = false

    var body: some View {
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

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
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

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
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

/// A restrained, native-feeling metadata label: an optional SF Symbol plus
/// secondary text, with no coloured capsule. This is the default treatment for
/// informational status (account, team, language, interview type, execution…) so
/// colour stays reserved for the one or two states that genuinely need to pop —
/// see ``StateBadge`` and the few remaining tinted ``Chip`` uses (e.g. "Draft").
struct MetaLabel: View {
    let text: String
    var systemImage: String?

    var body: some View {
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

// MARK: - ReloadToolbarButton

/// The Reload action shared by every section's window toolbar. Kept as a stable
/// `Label` (rather than swapping the whole control for a `ProgressView` while
/// loading) so the toolbar item keeps a fixed size and identity inside the
/// Liquid Glass cluster, and so the "Icon and Text" customization mode always has
/// text to show. The spinning feedback comes from a symbol effect on the icon.
struct ReloadToolbarButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Reload", systemImage: "arrow.clockwise")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading)
        }
        .help("Reload")
        .accessibilityLabel("Reload")
        .disabled(isLoading)
    }
}
