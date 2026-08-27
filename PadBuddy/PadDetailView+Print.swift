//
//  PadDetailView+Print.swift
//  coderpad
//

import SwiftUI

/// Message for a failed pad print, or nil when the user cancelled the panel (#4666).
nonisolated func padPrintFailureMessage(for error: any Error) -> String? {
    guard !(error is CancellationError) else { return nil }

    return error.localizedDescription
}

extension PadDetailView {
    /// Renders the pad as a vector document with its canonical source URL on
    /// every page, shared by the macOS and iPad print entry points.
    func printPadDocument() {
        #if os(macOS) || os(iOS)
            let identityPolicy: PadSummaryIdentityPolicy = GeneralSettings.includeIdentitiesInPadExports
                ? .include
                : .redact
            let sourceURL = pad.webURL ?? client.baseURL
            let configuration = PrintableView.PrintConfiguration(
                footer: .attribution(sourceURL: sourceURL),
                jobTitle: pad.title.isEmpty ? pad.id : pad.title
            )
            Task { @MainActor in
                do {
                    _ = try await PrintableView.printDocument(configuration: configuration) {
                        PadPrintDocument(pad: pad, files: printFiles(), identityPolicy: identityPolicy,
                                         displayName: directory.display)
                    }
                } catch {
                    if let message = padPrintFailureMessage(for: error) {
                        mutateError = message
                    }
                }
            }
        #endif
    }
}
