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
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.subtleStroke, lineWidth: 1))
        .padding(.bottom, 12)
    }
}
