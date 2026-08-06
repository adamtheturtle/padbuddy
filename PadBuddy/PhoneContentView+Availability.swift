//
//  PhoneContentView+Availability.swift
//  coderpad
//
//  Which sections the compact shell can show, split from PhoneContentView.swift to
//  keep that file under the file-length and type-body limits. `quotaIsUnlimited` and
//  `screenSectionAvailable` are internal rather than private so they are reachable
//  from there.
//

#if os(iOS)
    import SwiftUI

    extension PhoneContentView {
        /// Whether the current account's plan is unlimited (no Quota tab), read from
        /// the quota cache exactly like `Sidebar.quotaIsUnlimited`; reading it in
        /// `body` (via `onChange`) also makes the cache observable here, so the tab
        /// set re-evaluates when the session load reveals an unlimited plan.
        var quotaIsUnlimited: Bool {
            guard !store.isMergedView, let id = store.currentAccountID else { return false }

            return QuotaCacheStore.shared.get(id)?.unlimited == true
        }

        /// Whether the Screen tab should appear, mirroring `Sidebar.screenSectionAvailable`.
        var screenSectionAvailable: Bool {
            if store.isMergedView {
                return store.mergeableAccounts.contains(where: \.hasScreenAccess)
            }
            return store.currentAccount?.hasScreenAccess == true
        }

        func clearNavigationState() {
            padSelection = nil
            questionSelection = nil
            padPath = []
            questionPath = []
            screenPath = []
            windowNav.publishScreenCampaign(nil, accountID: nil)
            // The Screen detail's published subtitle/owner belong to the previous
            // account's drill-down; left behind, a later Screen detail inherited
            // another account's subtitle and routing (#1668).
            windowNav.screenTestsSubtitle = ""
            windowNav.screenTestsSubtitleOwner = nil
            // A new organization must not open pre-filtered by the previous
            // account's searches (#1683).
            padSearch = ""
            questionSearch = ""
            screenSearch = ""
        }
    }
#endif
