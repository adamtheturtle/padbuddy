//
//  PadDetailView+Print.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    /// Renders the pad as a vector document with its canonical source URL on
    /// every page, shared by the macOS and iPad print entry points.
    func printPadDocument() {
        let identityPolicy: PadSummaryIdentityPolicy = GeneralSettings.includeIdentitiesInPadExports
            ? .include
            : .redact
        let sourceURL = pad.webURL ?? client.baseURL
        let configuration = PrintableView.PrintConfiguration(
            footer: .attribution(sourceURL: sourceURL),
            jobTitle: pad.title.isEmpty ? pad.id : pad.title
        )
        try? PrintableView.printDocument(configuration: configuration) {
            PadPrintDocument(pad: pad, files: printFiles(), identityPolicy: identityPolicy,
                             displayName: directory.display)
        }
    }
}
