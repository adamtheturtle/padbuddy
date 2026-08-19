//
//  Tokens.swift
//  CoderPadDesignSystem
//
//  Colour, spacing, and contrast tokens shared across the design-system primitives.
//

import AppKit
import SwiftUI

public extension Color {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleStroke = Color.primary.opacity(0.08)
    /// The neutral capsule fill an *idle* filter chip wears on macOS 15 so every chip
    /// in the bar reads as a control rather than bare text + chevron (#352). On
    /// macOS 26 the chips use Liquid Glass instead; this is the fallback, bumped from
    /// a near-invisible 6% so it still plainly reads as a filled control on Sequoia.
    static let chipIdleFill = Color.primary.opacity(0.11)

    /// Parses an "#RRGGBB" (or "RRGGBB") hex string into an sRGB color, or `nil` if
    /// it isn't a well-formed six-digit hex value.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") {
            string.removeFirst()
        }
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

        return Self.hexString(
            red: resolved.redComponent,
            green: resolved.greenComponent,
            blue: resolved.blueComponent
        )
    }

    static func hexString(red: CGFloat, green: CGFloat, blue: CGFloat) -> String? {
        let components = [red, green, blue]
        guard components.allSatisfy(\.isFinite) else { return nil }

        let bytes = components.map { component in
            Int((min(1, max(0, component)) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

/// Shared layout constants so pane chrome stays in sync across detail views.
/// Tweak these here instead of hunting for matching literals in every view.
public enum Spacing {
    /// Horizontal inset for pane content.
    public static let paneH: CGFloat = 22
    /// Vertical inset for pane content (its top gap below the toolbar and its
    /// bottom padding).
    public static let paneV: CGFloat = 22
    /// Interior padding for ``Card``.
    public static let card: CGFloat = 16
    /// Horizontal inset for the inline banner.
    public static let bannerH: CGFloat = 14
}

/// Contrast-aware opacities for the app's tinted chips and badges. Their default
/// fills are deliberately subtle; under the system "Increase Contrast"
/// accessibility setting they're raised (and the hairline stroke thickened) so
/// the controls stay legible for low-vision users.
public enum ChipContrast {
    public static func fill(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.2) : base
    }

    public static func stroke(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.4) : base
    }

    public static func lineWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 1 : 0.5
    }
}
