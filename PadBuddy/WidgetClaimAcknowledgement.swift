//
//  WidgetClaimAcknowledgement.swift
//  PadBuddy
//

import Foundation

nonisolated extension WidgetSharedStore {
    static func acknowledgementFailure(
        context: String,
        acknowledge: () throws -> Void
    ) -> String? {
        do {
            try acknowledge()
            return nil
        } catch {
            return "\(context): \(error.localizedDescription)"
        }
    }
}
