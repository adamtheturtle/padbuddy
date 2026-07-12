#if os(macOS)
//
    //  AboutPanel.swift
    //  coderpad
//

    import AppKit

    let copyrightLine = "Copyright © 2026 Adam Dangoor"

    /// Shows the app's custom About panel, populated with version, build, credits,
    /// and copyright. Shared by the app menu and the menu-bar extra so both surface
    /// the same information.
    func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        AppActivator.bringToFront()
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "PadBuddy",
            NSApplication.AboutPanelOptionKey.applicationVersion: version,
            NSApplication.AboutPanelOptionKey.version: "Build \(build)",
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyrightLine,
            // The unofficial-client / trademark disclaimer (#40, #491) lives here in the
            // standard About panel — its natural home — so it survives even though the
            // Settings "About" section was removed (#496).
            NSApplication.AboutPanelOptionKey.credits: aboutCreditsDisclaimer
        ])
    }

    /// The unofficial-client and trademark disclaimer shown as credits in the About
    /// panel. Centered, secondary-styled text. Phrased as "This app" so it stays
    /// correct regardless of the app's display name.
    private var aboutCreditsDisclaimer: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: String(localized: """
            This app is an unofficial client for the CoderPad interview platform. \
            It is not affiliated with, authorized, maintained, or endorsed by CoderPad, Inc. \
            “CoderPad” is a trademark of CoderPad, Inc.
            """),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
    }
#endif
