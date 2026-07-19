//
//  MergedScreenView+SelectionValidity.swift
//  coderpad
//

import Foundation

nonisolated enum ScreenCampaignSelectionValidity {
    static func accountID(from scopedID: String?) -> UUID? {
        guard let scopedID,
              let separator = scopedID.firstIndex(of: ":") else { return nil }

        return UUID(uuidString: String(scopedID[..<separator]))
    }

    static func shouldRevoke(scopedID: String?, failedAccountID: UUID) -> Bool {
        accountID(from: scopedID) == failedAccountID
    }
}
