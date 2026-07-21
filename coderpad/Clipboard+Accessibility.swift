//
//  Clipboard+Accessibility.swift
//  coderpad
//

import BuddyAppKit
import Foundation
import SwiftUI

/// App-facing clipboard seam that adds consistent assistive feedback to the
/// package's platform pasteboard writer.
enum Clipboard {
    static func copy(_ text: String) {
        BuddyAppKit.Clipboard.copy(text)
        AccessibilityNotification.Announcement("Copied to clipboard").post()
    }

    static func copy(_ text: String, rtf: Data?) {
        BuddyAppKit.Clipboard.copy(text, rtf: rtf)
        AccessibilityNotification.Announcement("Copied to clipboard").post()
    }
}
