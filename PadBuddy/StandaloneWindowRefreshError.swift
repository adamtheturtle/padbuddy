//
//  StandaloneWindowRefreshError.swift
//  coderpad
//

import SwiftUI

struct StandaloneAccountBanner: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .accessibilityHidden(true)
            Text("Account: \(name)")
                .font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.paneH)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

/// Privacy-safe, localized copy for stale standalone-window content. Backend and
/// proxy descriptions are untrusted diagnostics and must not be rendered verbatim.
enum StandaloneWindowRefreshError {
    case pad
    case question
    case screenTest

    var message: String {
        switch self {
        case .pad: String(localized: "Could not refresh this pad. Try again.")
        case .question: String(localized: "Could not refresh this question. Try again.")
        case .screenTest: String(localized: "Could not refresh this Screen test. Try again.")
        }
    }
}

nonisolated enum StandaloneWindowResponse {
    static func matches(requestedQuestionID: Int, responseID: Int) -> Bool {
        requestedQuestionID == responseID
    }

    static func matches(requestedPadID: String, responseID: String) -> Bool {
        requestedPadID == responseID
    }

    static func matches(requestedScreenTestID: Int, responseID: Int) -> Bool {
        requestedScreenTestID == responseID
    }
}

nonisolated enum StandaloneWindowResponseError: Error {
    case mismatchedID
}
