//
//  Clipboard.swift
//  coderpad
//
//  A thin seam over the system pasteboard so plain-text clipboard writes go through
//  one place instead of scattering `NSPasteboard` across the views. Keeping this
//  incidental AppKit API behind a single helper is a step toward multi-platform
//  portability (#287): a future iOS/iPadOS build can swap the body for `UIPasteboard`
//  without touching any call site.
//

import AppKit

enum Clipboard {
    /// Replace the pasteboard contents with `text` as a plain string.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
