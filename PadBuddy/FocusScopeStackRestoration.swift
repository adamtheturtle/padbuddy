//
//  FocusScopeStackRestoration.swift
//  PadBuddy
//

import Foundation

nonisolated enum FocusScopeStackRestoration {
    case current(FocusScopeStack)
    case stale
    case failed(String)

    static func decode(
        _ data: Data,
        expectedSessionID: String,
        using decode: (Data) throws -> FocusScopeStack = {
            try JSONDecoder().decode(FocusScopeStack.self, from: $0)
        }
    ) -> Self {
        do {
            let stack = try decode(data)
            return stack.sessionID == expectedSessionID ? .current(stack) : .stale
        } catch {
            return .failed("Could not restore the Focus account scope stack: \(error.localizedDescription)")
        }
    }
}
