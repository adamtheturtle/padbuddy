//
//  TouchTarget.swift
//  coderpad
//
//  A small platform-gated helper for Apple's 44x44pt minimum touch target (#597).
//  Many controls are shared with the macOS layout, where they were tuned for a mouse
//  pointer (icon-only, .plain/.borderless, caption glyphs, no padding) and are fiddly
//  to hit on iPad touch. `touchTarget()` enlarges the *hit* area on touch platforms
//  without changing the glyph, and is a no-op on macOS so the compact pointer layout
//  stays byte-identical.
//

import SwiftUI

extension View {
    /// Guarantees at least a `side` x `side` hit target on touch platforms (Apple's
    /// 44pt HIG minimum), expanding the tappable frame around the (unchanged) content
    /// and making the whole frame hittable. A no-op on macOS, where the pointer-tuned
    /// resting layout should stay compact and unchanged.
    func touchTarget(_ side: CGFloat = 44) -> some View {
        #if os(macOS)
            self
        #else
            frame(minWidth: side, minHeight: side).contentShape(Rectangle())
        #endif
    }
}
