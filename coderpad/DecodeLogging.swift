//
//  DecodeLogging.swift
//  coderpad
//
//  The tolerant, logged decode helper used by the app's own decode-only models (e.g.
//  `ScreenAPI`). It previously lived alongside the CoderPad API client; that client
//  moved to the `CoderPadKit` package (#569, which keeps its own internal copy), so the
//  app keeps this one for the models that stayed behind.
//

import Foundation
import os.log

private nonisolated let decodeLogger = Logger(subsystem: "com.coderpad.app", category: "decode")

extension KeyedDecodingContainer {
    /// Like `try? decodeIfPresent`, but logs the underlying error so silent API drift
    /// shows up in Console rather than producing an empty UI with no diagnostic.
    nonisolated func loggedDecodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            decodeLogger.debug(
                """
                decodeIfPresent '\(key.stringValue, privacy: .public)' \
                as \(String(describing: type), privacy: .public) \
                failed: \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }
}
