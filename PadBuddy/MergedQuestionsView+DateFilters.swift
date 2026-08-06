//
//  MergedQuestionsView+DateFilters.swift
//  coderpad
//

import Foundation

extension MergedQuestionsView {
    var activeFilterCount: Int {
        [languageFilter, ownerFilter, typeFilter, draftFilter].compactMap(\.self).count
            + (accountFilter != nil ? 1 : 0)
            + (mineOnly ? 1 : 0)
            + (favoritesOnly ? 1 : 0)
            + (updatedWindow.isActive ? 1 : 0)
            + (createdWindow.isActive ? 1 : 0)
    }

    var filterSignature: FilterSignature {
        FilterSignature.make([
            search.trimmingCharacters(in: .whitespacesAndNewlines),
            languageFilter,
            ownerFilter,
            typeFilter,
            draftFilter,
            accountFilter?.uuidString,
            mineOnly ? "mine" : nil,
            favoritesOnly ? "favorites" : nil,
            updatedWindow.signatureToken,
            createdWindow.signatureToken,
            dateFilterClockTick.description
        ])
    }

    func matchesDateFilters(_ question: Question, now: Date) -> Bool {
        let matchesUpdated = !updatedWindow.isActive || question.updatedAt.map {
            PadDateWindowValidation.contains(updatedWindow, date: $0, now: now)
        } == true
        let matchesCreated = !createdWindow.isActive || question.createdAt.map {
            PadDateWindowValidation.contains(createdWindow, date: $0, now: now)
        } == true
        return matchesUpdated && matchesCreated
    }

    var dateFilterClockActive: Bool {
        updatedWindow.isActive || createdWindow.isActive
    }

    func runDateFilterClock() async {
        guard dateFilterClockActive else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }

            dateFilterClockTick &+= 1
        }
    }
}
