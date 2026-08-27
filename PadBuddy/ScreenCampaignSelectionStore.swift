//
//  ScreenCampaignSelectionStore.swift
//  coderpad
//

import Foundation

enum ScreenCampaignSelectionStore {
    private static let singlePrefix = "screen.selectedCampaign.v1"
    private static let mergedKey = "screen.selectedMergedCampaign.v1"

    /// A merged selection is `<account UUID>:<campaign id>`. Only that shape can resolve
    /// back to a campaign, so anything else is not a selection worth keeping.
    static func validatedMergedCampaign(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              UUID(uuidString: String(parts[0])) != nil,
              let campaign = Int(parts[1]), campaign > 0 else { return nil }

        return trimmed
    }

    static func campaign(for account: UUID) -> Int? {
        let key = singleKey(account)
        let value = UserDefaults.standard.integer(forKey: key)
        guard value > 0 else {
            // A stored id the reader will never accept is not a selection; clear it so it
            // stops being re-read on every restoration.
            if UserDefaults.standard.object(forKey: key) != nil {
                UserDefaults.standard.removeObject(forKey: key)
            }
            return nil
        }

        return value
    }

    /// Campaign ids are positive, and `campaign(for:)` restores only positive values.
    /// Persisting `0` or a negative id succeeded silently and then read back as nil, so a
    /// selection appeared to save and vanished at the next view recreation (#4574).
    static func save(_ campaign: Int?, for account: UUID) {
        let key = singleKey(account)
        guard let campaign, campaign > 0 else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        UserDefaults.standard.set(campaign, forKey: key)
    }

    /// Storing `""` — or any unresolvable string — kept a non-nil selection that no
    /// campaign could satisfy, which the detail column reads as "still loading" and so
    /// stays blank (#4575). Only a resolvable scoped id is stored.
    static var mergedCampaign: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: mergedKey)
            guard let valid = validatedMergedCampaign(stored) else {
                if stored != nil {
                    UserDefaults.standard.removeObject(forKey: mergedKey)
                }
                return nil
            }

            return valid
        }
        set {
            guard let valid = validatedMergedCampaign(newValue) else {
                UserDefaults.standard.removeObject(forKey: mergedKey)
                return
            }

            UserDefaults.standard.set(valid, forKey: mergedKey)
        }
    }

    /// Drops a removed account's stored selection so it cannot be restored under a reused
    /// identifier.
    static func removeSelection(for account: UUID) {
        UserDefaults.standard.removeObject(forKey: singleKey(account))
        if let merged = UserDefaults.standard.string(forKey: mergedKey),
           merged.hasPrefix("\(account.uuidString):") {
            UserDefaults.standard.removeObject(forKey: mergedKey)
        }
    }

    private static func singleKey(_ account: UUID) -> String {
        "\(singlePrefix).\(account.uuidString)"
    }
}
