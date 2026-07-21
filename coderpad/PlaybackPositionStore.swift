//
//  PlaybackPositionStore.swift
//  coderpad
//

import Foundation
import SwiftUI

nonisolated enum PlaybackPositionStore {
    private static let defaultsKey = "padHistoryPlaybackPositions"

    static func key(for histories: [PadFileHistory]) -> String {
        histories.map(\.id).sorted().joined(separator: "\u{1F}")
    }

    static func timestamp(for key: String) -> Int64? {
        guard !key.isEmpty else { return nil }

        return savedPositions()[key]
    }

    static func position(in timeline: PadPlaybackTimeline, histories: [PadFileHistory]) -> Int {
        let savedTimestamp = timestamp(for: key(for: histories))
        guard let savedTimestamp else { return max(0, timeline.items.count - 1) }

        return timeline.items.lastIndex(where: { $0.timestamp <= savedTimestamp }) ?? 0
    }

    static func save(_ timestamp: Int64?, for key: String) {
        guard !key.isEmpty, let timestamp else { return }

        var positions = savedPositions()
        positions[key] = timestamp
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func savedPositions() -> [String: Int64] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [:] }

        return (try? JSONDecoder().decode([String: Int64].self, from: data)) ?? [:]
    }
}

private struct PlaybackPositionModifier: ViewModifier {
    @Binding var position: Int
    let timeline: PadPlaybackTimeline
    let histories: [PadFileHistory]
    let isPlaying: Bool

    func body(content: Content) -> some View {
        content.onChange(of: position) {
            let timestamp = timeline.items.indices.contains(position) ? timeline.items[position].timestamp : nil
            PlaybackPositionStore.save(timestamp,
                                       for: PlaybackPositionStore.key(for: histories))
            guard !isPlaying else { return }

            AccessibilityNotification.Announcement(
                String(localized: "History revision \(position + 1) of \(timeline.items.count)")
            ).post()
        }
    }
}

extension View {
    func persistPlaybackPosition(
        _ position: Binding<Int>, timeline: PadPlaybackTimeline,
        histories: [PadFileHistory], isPlaying: Bool
    ) -> some View {
        modifier(PlaybackPositionModifier(
            position: position, timeline: timeline, histories: histories, isPlaying: isPlaying
        ))
    }
}
