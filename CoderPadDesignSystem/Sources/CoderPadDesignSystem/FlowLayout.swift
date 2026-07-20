//
//  FlowLayout.swift
//  CoderPadDesignSystem
//
//  A reusable wrapping flow layout, backed by the Flow package's HFlow (#391/#377).
//

import Flow
import SwiftUI

func normalizedFlowSpacing(_ spacing: CGFloat) -> CGFloat {
    max(0, spacing)
}

/// Arranges its subviews left-to-right, wrapping to a new line whenever the next
/// subview would overflow the available width. Lets a row of chips reflow onto
/// multiple lines as its container narrows, instead of being clipped or forcing a
/// horizontal scroll.
///
/// A thin wrapper over the Flow package's `HFlow`: it pins the convention in one
/// place — left-aligned rows with items vertically centred, filling the available
/// width (HFlow sizes to its content, so a single partly-filled row would otherwise
/// be centred by a wider parent) — and maps `spacing` (gap between items in a row)
/// and `lineSpacing` (gap between rows) onto HFlow's horizontal/vertical spacing.
public struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = normalizedFlowSpacing(spacing)
        self.lineSpacing = normalizedFlowSpacing(lineSpacing)
        self.content = content
    }

    public var body: some View {
        HFlow(horizontalAlignment: .leading,
              verticalAlignment: .center,
              horizontalSpacing: spacing,
              verticalSpacing: lineSpacing) {
            content()
        }
        // Fill the available width and pin to the leading edge; HFlow sizes to its
        // content, so without this a single, partly-filled row would be centred by a
        // wider parent (#391).
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
