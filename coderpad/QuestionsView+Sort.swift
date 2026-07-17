//
//  QuestionsView+Sort.swift
//  coderpad
//

import SwiftUI

/// Sort orders offered for the Questions list. "Last used" is backed by the
/// question's `updatedAt` timestamp — the API exposes no distinct last-used date.
enum QuestionSort: String, CaseIterable, Identifiable {
    case lastUsedDesc
    case lastUsedAsc
    case usedDesc
    case usedAsc
    case titleAsc
    case titleDesc

    /// `@AppStorage` key shared by both Questions lists and the Question menu's
    /// "Sort By" command, so changing the sort anywhere keeps them all in sync.
    static let storageKey = "questions.sort"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .lastUsedDesc: String(localized: "Last used (newest first)")
        case .lastUsedAsc: String(localized: "Last used (oldest first)")
        case .usedDesc: String(localized: "Most used")
        case .usedAsc: String(localized: "Least used")
        case .titleAsc: String(localized: "Title (A-Z)")
        case .titleDesc: String(localized: "Title (Z-A)")
        }
    }

    /// The field this sort orders by, independent of direction.
    var field: QuestionSortField {
        switch self {
        case .lastUsedDesc, .lastUsedAsc: .lastUsed
        case .usedDesc, .usedAsc: .used
        case .titleAsc, .titleDesc: .title
        }
    }

    /// The two directions available for `field`, in menu order, each with a
    /// field-appropriate label and arrow (e.g. "Newest First" / "Oldest First" for
    /// a date field, "A to Z" / "Z to A" for the title). The first is the default.
    static func directions(for field: QuestionSortField) -> [QuestionSortDirection] {
        switch field {
        case .lastUsed:
            [QuestionSortDirection(sort: .lastUsedDesc,
                                   label: String(localized: "Newest First"), systemImage: "arrow.down"),
             QuestionSortDirection(sort: .lastUsedAsc,
                                   label: String(localized: "Oldest First"), systemImage: "arrow.up")]

        case .used:
            [QuestionSortDirection(sort: .usedDesc,
                                   label: String(localized: "Most Used"), systemImage: "arrow.down"),
             QuestionSortDirection(sort: .usedAsc,
                                   label: String(localized: "Least Used"), systemImage: "arrow.up")]

        case .title:
            [QuestionSortDirection(sort: .titleAsc,
                                   label: String(localized: "A to Z"), systemImage: "arrow.down"),
             QuestionSortDirection(sort: .titleDesc,
                                   label: String(localized: "Z to A"), systemImage: "arrow.up")]
        }
    }

    /// Switching to `field` while keeping the current direction slot (so toggling
    /// the field doesn't reset newest↔oldest).
    func withField(_ newField: QuestionSortField) -> Self {
        let slot = Self.directions(for: field).firstIndex { $0.sort == self } ?? 0
        let options = Self.directions(for: newField)
        return options[min(slot, options.count - 1)].sort
    }

    /// Arrange question-backed rows by this sort. "Last used" is backed by
    /// `updatedAt` — the only per-question recency signal the API exposes.
    func sorted<C: Collection>(_ items: C, question: (C.Element) -> Question) -> [C.Element] {
        sorted(items, question: question, tieBreaker: { question($0).id })
    }

    func sorted<C: Collection>(
        _ items: C,
        question: (C.Element) -> Question,
        tieBreaker: (C.Element) -> some Comparable
    ) -> [C.Element] {
        switch self {
        case .titleAsc:
            items.sorted {
                let lhs = question($0).displayTitle
                let rhs = question($1).displayTitle
                return compare(lhs, rhs, .orderedAscending, tieBreaker($0), tieBreaker($1))
            }

        case .titleDesc:
            items.sorted {
                let lhs = question($0).displayTitle
                let rhs = question($1).displayTitle
                return compare(lhs, rhs, .orderedDescending, tieBreaker($0), tieBreaker($1))
            }

        case .lastUsedDesc:
            items.sorted { lhsItem, rhsItem in
                compare(
                    question(lhsItem).updatedAt ?? .distantPast,
                    question(rhsItem).updatedAt ?? .distantPast,
                    >,
                    tieBreaker(lhsItem),
                    tieBreaker(rhsItem)
                )
            }

        case .lastUsedAsc:
            items.sorted { lhsItem, rhsItem in
                compare(
                    question(lhsItem).updatedAt ?? .distantPast,
                    question(rhsItem).updatedAt ?? .distantPast,
                    <,
                    tieBreaker(lhsItem),
                    tieBreaker(rhsItem)
                )
            }

        case .usedDesc:
            items.sorted { compare(question($0).used ?? 0, question($1).used ?? 0, >, tieBreaker($0), tieBreaker($1)) }

        case .usedAsc:
            items.sorted { compare(question($0).used ?? 0, question($1).used ?? 0, <, tieBreaker($0), tieBreaker($1)) }
        }
    }

    func sorted(_ items: some Collection<Question>) -> [Question] {
        sorted(items) { $0 }
    }

    private func compare<T: Equatable, TieBreaker: Comparable>(
        _ lhs: T,
        _ rhs: T,
        _ ordered: (T, T) -> Bool,
        _ lhsTieBreaker: TieBreaker,
        _ rhsTieBreaker: TieBreaker
    ) -> Bool {
        guard lhs != rhs else { return lhsTieBreaker < rhsTieBreaker }

        return ordered(lhs, rhs)
    }

    private func compare<TieBreaker: Comparable>(
        _ lhs: String,
        _ rhs: String,
        _ ordered: ComparisonResult,
        _ lhsTieBreaker: TieBreaker,
        _ rhsTieBreaker: TieBreaker
    ) -> Bool {
        let result = lhs.localizedCaseInsensitiveCompare(rhs)
        guard result != .orderedSame else { return lhsTieBreaker < rhsTieBreaker }

        return result == ordered
    }
}

/// One direction option for a ``QuestionSortField``: the concrete ``QuestionSort``
/// it applies, plus a field-appropriate label and arrow for the Sort menu.
struct QuestionSortDirection {
    let sort: QuestionSort
    let label: String
    let systemImage: String
}

/// The field a ``QuestionSort`` orders by. Pairs with a direction to form the full
/// sort, so the Sort menu can offer field and direction as two sections (à la the
/// Passwords app) rather than one list of combined options.
enum QuestionSortField: String, CaseIterable, Identifiable {
    case lastUsed
    case used
    case title

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .lastUsed: String(localized: "Last Used")
        case .used: String(localized: "Times Used")
        case .title: String(localized: "Title")
        }
    }

    var systemImage: String {
        switch self {
        case .lastUsed: "clock"
        case .used: "chart.bar"
        case .title: "textformat"
        }
    }
}

/// The Sort menu's contents, shared by the Questions toolbar button and the
/// Question menu's "Sort By" command so they stay in lockstep. Two inline radio
/// sections — sort field, then direction — mirroring the Passwords app.
struct QuestionSortMenuContent: View {
    @Binding var sort: QuestionSort

    var body: some View {
        Picker("Sort By", selection: Binding(get: { sort.field }, set: { sort = sort.withField($0) })) {
            ForEach(QuestionSortField.allCases) { field in
                Label(field.label, systemImage: field.systemImage).tag(field)
            }
        }
        .pickerStyle(.inline)

        Picker("Order", selection: $sort) {
            ForEach(QuestionSort.directions(for: sort.field), id: \.sort) { option in
                Label(option.label, systemImage: option.systemImage).tag(option.sort)
            }
        }
        .pickerStyle(.inline)
    }
}

extension Question {
    /// Title to display, falling back to `#id` when a question has no title.
    var displayTitle: String {
        title.isEmpty ? "#\(id)" : title
    }
}
