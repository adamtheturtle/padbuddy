//
//  PadsView+Sort.swift
//  coderpad
//

import SwiftUI

/// Sort orders offered for the Pads list. Mirrors ``QuestionSort`` so both lists
/// expose the same field/direction Sort menu (#361).
enum PadSort: String, CaseIterable, Identifiable {
    case updatedDesc
    case updatedAsc
    case createdDesc
    case createdAsc
    case titleAsc
    case titleDesc

    /// `@AppStorage` key shared by both Pads lists and the Pad menu's "Sort By"
    /// command, so changing the sort anywhere keeps them all in sync.
    static let storageKey = "pads.sort"

    var id: String {
        rawValue
    }

    /// The field this sort orders by, independent of direction.
    var field: PadSortField {
        switch self {
        case .updatedDesc, .updatedAsc: .updated
        case .createdDesc, .createdAsc: .created
        case .titleAsc, .titleDesc: .title
        }
    }

    /// The two directions available for `field`, in menu order, each with a
    /// field-appropriate label and arrow. The first is the default.
    static func directions(for field: PadSortField) -> [PadSortDirection] {
        switch field {
        case .updated:
            [PadSortDirection(sort: .updatedDesc,
                              label: String(localized: "Newest First"), systemImage: "arrow.down"),
             PadSortDirection(sort: .updatedAsc,
                              label: String(localized: "Oldest First"), systemImage: "arrow.up")]

        case .created:
            [PadSortDirection(sort: .createdDesc,
                              label: String(localized: "Newest First"), systemImage: "arrow.down"),
             PadSortDirection(sort: .createdAsc,
                              label: String(localized: "Oldest First"), systemImage: "arrow.up")]

        case .title:
            [PadSortDirection(sort: .titleAsc,
                              label: String(localized: "A to Z"), systemImage: "arrow.down"),
             PadSortDirection(sort: .titleDesc,
                              label: String(localized: "Z to A"), systemImage: "arrow.up")]
        }
    }

    /// Switching to `field` while keeping the current direction slot (so toggling
    /// the field doesn't reset newest↔oldest).
    func withField(_ newField: PadSortField) -> Self {
        let slot = Self.directions(for: field).firstIndex { $0.sort == self } ?? 0
        let options = Self.directions(for: newField)
        return options[min(slot, options.count - 1)].sort
    }
}

/// One direction option for a ``PadSortField``: the concrete ``PadSort`` it
/// applies, plus a field-appropriate label and arrow for the Sort menu.
struct PadSortDirection {
    let sort: PadSort
    let label: String
    let systemImage: String
}

/// The field a ``PadSort`` orders by. Pairs with a direction to form the full
/// sort, so the Sort menu can offer field and direction as two sections.
enum PadSortField: String, CaseIterable, Identifiable {
    case updated
    case created
    case title

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .updated: String(localized: "Last Updated")
        case .created: String(localized: "Date Created")
        case .title: String(localized: "Title")
        }
    }

    var systemImage: String {
        switch self {
        case .updated: "clock"
        case .created: "calendar"
        case .title: "textformat"
        }
    }
}

/// The Sort menu's contents, shared by the Pads toolbar button and the Pad menu's
/// "Sort By" command so they stay in lockstep. Two inline radio sections — sort
/// field, then direction — mirroring the Questions list.
struct PadSortMenuContent: View {
    @Binding var sort: PadSort

    var body: some View {
        Picker("Sort By", selection: Binding(get: { sort.field }, set: { sort = sort.withField($0) })) {
            ForEach(PadSortField.allCases) { field in
                Label(field.label, systemImage: field.systemImage).tag(field)
            }
        }
        .pickerStyle(.inline)

        Picker("Order", selection: $sort) {
            ForEach(PadSort.directions(for: sort.field), id: \.sort) { option in
                Label(option.label, systemImage: option.systemImage).tag(option.sort)
            }
        }
        .pickerStyle(.inline)
    }
}

extension PadSort {
    /// Orders `pads` by the active sort. Title sort falls back to the pad id when a
    /// pad has no title, matching how the list renders an untitled pad.
    func sorted(_ pads: [Pad]) -> [Pad] {
        sorted(pads, by: { $0 })
    }

    /// Orders any items by their backing pad, so both the single-account list
    /// (`[Pad]`) and the merged list (`[AccountScoped<Pad>]`) share one ordering.
    func sorted<T>(_ items: [T], by pad: (T) -> Pad) -> [T] {
        sorted(items, by: pad, tieBreaker: { pad($0).id })
    }

    func sorted<T>(_ items: [T], by pad: (T) -> Pad, tieBreaker: (T) -> String) -> [T] {
        items.sorted {
            precedes(pad($0), pad($1), lhsTieBreaker: tieBreaker($0), rhsTieBreaker: tieBreaker($1))
        }
    }

    /// Whether `lhs` sorts before `rhs` under this order.
    private func precedes(_ lhs: Pad, _ rhs: Pad, lhsTieBreaker: String, rhsTieBreaker: String) -> Bool {
        switch self {
        case .updatedDesc:
            compare(lhs.updatedAt ?? .distantPast, rhs.updatedAt ?? .distantPast, >, lhsTieBreaker, rhsTieBreaker)
        case .updatedAsc:
            compare(lhs.updatedAt ?? .distantPast, rhs.updatedAt ?? .distantPast, <, lhsTieBreaker, rhsTieBreaker)
        case .createdDesc:
            compare(lhs.createdAt ?? .distantPast, rhs.createdAt ?? .distantPast, >, lhsTieBreaker, rhsTieBreaker)
        case .createdAsc:
            compare(lhs.createdAt ?? .distantPast, rhs.createdAt ?? .distantPast, <, lhsTieBreaker, rhsTieBreaker)
        case .titleAsc:
            compare(sortTitle(lhs), sortTitle(rhs), .orderedAscending, lhsTieBreaker, rhsTieBreaker)
        case .titleDesc:
            compare(sortTitle(lhs), sortTitle(rhs), .orderedDescending, lhsTieBreaker, rhsTieBreaker)
        }
    }

    private func sortTitle(_ pad: Pad) -> String {
        pad.title.isEmpty ? pad.id : pad.title
    }

    private func compare<T: Equatable>(
        _ lhs: T,
        _ rhs: T,
        _ ordered: (T, T) -> Bool,
        _ lhsTieBreaker: String,
        _ rhsTieBreaker: String
    ) -> Bool {
        guard lhs != rhs else { return lhsTieBreaker < rhsTieBreaker }

        return ordered(lhs, rhs)
    }

    private func compare(
        _ lhs: String,
        _ rhs: String,
        _ ordered: ComparisonResult,
        _ lhsTieBreaker: String,
        _ rhsTieBreaker: String
    ) -> Bool {
        let result = lhs.localizedCaseInsensitiveCompare(rhs)
        guard result != .orderedSame else { return lhsTieBreaker < rhsTieBreaker }

        return result == ordered
    }
}
