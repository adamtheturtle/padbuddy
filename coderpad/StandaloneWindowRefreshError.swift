//
//  StandaloneWindowRefreshError.swift
//  coderpad
//

import Foundation

/// Privacy-safe, localized copy for stale standalone-window content. Backend and
/// proxy descriptions are untrusted diagnostics and must not be rendered verbatim.
enum StandaloneWindowRefreshError {
    case pad
    case question
    case screenTest

    var message: String {
        switch self {
        case .pad: String(localized: "Couldn’t refresh this pad. Try again.")
        case .question: String(localized: "Couldn’t refresh this question. Try again.")
        case .screenTest: String(localized: "Couldn’t refresh this Screen test. Try again.")
        }
    }
}
