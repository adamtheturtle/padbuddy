//
//  FavoriteQuestionRefresh.swift
//  coderpad
//

import Foundation

enum FavoriteQuestionRefresh {
    static func reconcile(
        _ entries: [FavoriteQuestion],
        authoritativeTitles: [Int: String]
    ) -> (entries: [FavoriteQuestion], removedIDs: [Int]) {
        var refreshed: [FavoriteQuestion] = []
        var removedIDs: [Int] = []
        refreshed.reserveCapacity(entries.count)
        for var entry in entries {
            guard let title = authoritativeTitles[entry.id] else {
                removedIDs.append(entry.id)
                continue
            }

            // The authoritative refresh is another title-capture path, so enforce
            // the same bound as add, toggle, local decode, and cloud adoption before
            // the value reaches live state or persistence (#5143).
            entry.title = FavoriteQuestionsStore.boundedTitle(title)
            refreshed.append(entry)
        }
        return (refreshed, removedIDs)
    }
}
