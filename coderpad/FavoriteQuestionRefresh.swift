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

            entry.title = title
            refreshed.append(entry)
        }
        return (refreshed, removedIDs)
    }
}
