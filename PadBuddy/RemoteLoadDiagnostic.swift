import Foundation
import os

nonisolated enum RemoteLoadDiagnostic {
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "remote-load")

    static func display(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let diagnostic = ExternalText.singleLine(raw, limit: 2048)
        logger.warning("Remote load diagnostic: \(diagnostic, privacy: .private)")
        return ExternalText.singleLine(raw, limit: 512)
    }
}
