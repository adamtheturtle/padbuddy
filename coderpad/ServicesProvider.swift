//
//  ServicesProvider.swift
//  coderpad
//
//  Backs the "Open Pad in CoderPad" macOS Service. From any app — Safari, Notes,
//  Mail — a user can select a CoderPad pad link (or id) and choose this service
//  from the Services menu to open that pad here, without copy-pasting or switching
//  apps first. The service is declared in Info.plist (NSServices) and registered
//  via `NSApp.servicesProvider` at launch (see AppDelegate).
//

import AppKit
import Foundation

final class ServicesProvider: NSObject {
    // The @objc Service signature and the NSPasteboard URL reader below are
    // Objective-C bridging contracts, so NSString/NSURL are required here.
    // swiftlint:disable legacy_objc_type
    /// Handles the "Open Pad in CoderPad" service. The selection is routed through
    /// the app's own `coderpad://pad/<id>` deep link via LaunchServices — the same
    /// path the Recent Pads widget and Dock menu use — so it reliably launches or
    /// activates the app and opens a window before the link is delivered, with no
    /// in-process timing race. The `NSMessage` key in Info.plist names this method.
    @objc func openPad(_ pasteboard: NSPasteboard,
                       userData _: String?,
                       error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        guard let id = Self.padID(from: pasteboard) else {
            error?.pointee = "No CoderPad pad link or id was found in the selection." as NSString
            return
        }
        guard let deepLink = URL(string: "coderpad://pad/\(id)") else { return }

        AppActivator.bringToFront()
        URLOpener.open(deepLink)
    }

    /// Extracts a pad id from the service pasteboard, preferring a real URL item
    /// over selected text (Safari sends both for a selected link).
    static func padID(from pasteboard: NSPasteboard) -> String? {
        if let url = NSURL(from: pasteboard) as URL?, let id = padID(fromSelection: url.absoluteString) {
            return id
        }
        if let text = pasteboard.string(forType: .string) {
            return padID(fromSelection: text)
        }
        return nil
    }

    // swiftlint:enable legacy_objc_type

    /// Pure string → id extraction, kept separate so it's unit-testable. Accepts a
    /// CoderPad web URL (the id is its first path component), a `coderpad://pad/<id>`
    /// deep link, or a bare alphanumeric id token. Returns nil for anything else, so
    /// selecting arbitrary prose doesn't fire a bogus open.
    static func padID(fromSelection raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "coderpad" {
                let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return id.isEmpty ? nil : id
            }
            if scheme == "http" || scheme == "https" {
                // The pad id is the first real path component, e.g.
                // https://app.coderpad.io/ABC123 or .../ABC123/playback.
                return url.pathComponents.first { $0 != "/" && !$0.isEmpty }
            }
        }

        // A bare token with no URL structure: accept it as the id only when it
        // looks like one (alphanumeric), so a sentence of selected text is ignored.
        guard !trimmed.contains(where: \.isWhitespace),
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }

        return trimmed
    }
}
