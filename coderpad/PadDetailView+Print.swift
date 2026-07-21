//
//  PadDetailView+Print.swift
//  coderpad
//

extension PadDetailView {
    /// Renders the pad as a vector document with its canonical source URL on
    /// every page, shared by the macOS and iPad print entry points.
    func printPadDocument() {
        let identityPolicy: PadSummaryIdentityPolicy = GeneralSettings.includeIdentitiesInPadExports
            ? .include
            : .redact
        printAttributedDocument(
            PadPrintDocument(pad: pad, files: printFiles(), identityPolicy: identityPolicy,
                             displayName: directory.display),
            jobTitle: pad.title.isEmpty ? pad.id : pad.title,
            sourceURL: pad.webURL ?? client.baseURL
        )
    }
}
