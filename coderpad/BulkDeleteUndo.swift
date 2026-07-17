//
//  BulkDeleteUndo.swift
//  coderpad
//

import SwiftUI

struct PendingBulkDelete<Item>: Identifiable {
    let id = UUID()
    let items: [Item]
    let message: String
}

enum BulkDeleteUndo {
    static let gracePeriod: Duration = .seconds(5)

    static func mergedItems<Item: Identifiable>(
        existing: [Item],
        adding newItems: [Item]
    ) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in newItems where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }
}

struct BulkDeleteUndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .accessibilityHidden(true)
            Text(message)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 12)
    }
}
