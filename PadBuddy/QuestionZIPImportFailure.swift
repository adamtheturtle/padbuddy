//
//  QuestionZIPImportFailure.swift
//  PadBuddy
//

import Foundation

enum QuestionZIPSelectionError: LocalizedError, Equatable {
    case cannotRead
    case notRegularFile
    case tooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .cannotRead:
            String(localized: "The selected ZIP could not be read.")
        case .notRegularFile:
            String(localized: "Choose a regular ZIP file, not a folder or symbolic link.")
        case let .tooLarge(maximumBytes):
            String(localized: "Choose a ZIP file smaller than \(maximumBytes / 1024 / 1024) MB.")
        }
    }
}

nonisolated func questionZIPImportFailureMessage(_ error: any Error) -> String? {
    if error is CancellationError
        || (error as? CocoaError)?.code == .userCancelled
        || (error as? URLError)?.code == .cancelled {
        return nil
    }
    return String(localized: "Could not choose the project ZIP: \(error.localizedDescription)")
}
