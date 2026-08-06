//
//  ScreenCampaignSelectionStore.swift
//  coderpad
//

import Foundation

enum ScreenCampaignSelectionStore {
    private static let singlePrefix = "screen.selectedCampaign.v1"
    private static let mergedKey = "screen.selectedMergedCampaign.v1"

    static func campaign(for account: UUID) -> Int? {
        let value = UserDefaults.standard.integer(forKey: "\(singlePrefix).\(account.uuidString)")
        return value > 0 ? value : nil
    }

    static func save(_ campaign: Int?, for account: UUID) {
        let key = "\(singlePrefix).\(account.uuidString)"
        if let campaign {
            UserDefaults.standard.set(campaign, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static var mergedCampaign: String? {
        get { UserDefaults.standard.string(forKey: mergedKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: mergedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: mergedKey)
            }
        }
    }
}
