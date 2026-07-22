//
//  PadPlaybackTimeline+DisplayMapping.swift
//  coderpad
//

import Foundation

nonisolated extension PadPlaybackTimeline {
    struct DisplayMapping {
        let offsets: [Int64]
        let duration: Int64
        let compressedGaps: [CompressedGap]
    }

    private struct GapDraft {
        let afterIndex: Int
        let midpoint: Int64
        let actualSeconds: Double
    }

    static func displayMapping(for items: [PadPlaybackItem]) -> DisplayMapping {
        var offsets = items.isEmpty ? [] : [Int64(0)]
        var gaps: [GapDraft] = []
        var cumulative: Int64 = 0
        for index in 1 ..< items.count {
            let actual = items[index].timestamp - items[index - 1].timestamp
            let displayed = min(actual, maximumDisplayGapMilliseconds)
            if actual > maximumDisplayGapMilliseconds {
                gaps.append(GapDraft(
                    afterIndex: index - 1,
                    midpoint: cumulative + displayed / 2,
                    actualSeconds: Double(actual) / 1000
                ))
            }
            cumulative += displayed
            offsets.append(cumulative)
        }
        return DisplayMapping(
            offsets: offsets,
            duration: cumulative,
            compressedGaps: gaps.map {
                CompressedGap(
                    afterIndex: $0.afterIndex,
                    fraction: cumulative > 0 ? Double($0.midpoint) / Double(cumulative) : 0,
                    actualSeconds: $0.actualSeconds
                )
            }
        )
    }

    /// Where an item sits on the display track. Normal gaps retain wall-clock
    /// spacing; long inactive gaps are capped so they cannot dominate the track.
    func fraction(at index: Int) -> Double {
        guard items.count > 1, items.indices.contains(index) else { return 0 }
        guard displayDuration > 0 else { return Double(index) / Double(items.count - 1) }

        return Double(displayOffsets[index]) / Double(displayDuration)
    }

    /// Maps a real event instant into the same compressed display clock.
    func fraction(atMilliseconds milliseconds: Int64) -> Double? {
        guard endTimestamp > startTimestamp,
              milliseconds >= startTimestamp, milliseconds <= endTimestamp else { return nil }

        let upper = firstItemIndex(after: milliseconds)
        if upper == 0 { return 0 }
        if upper == items.count { return 1 }

        let lower = upper - 1
        let actualGap = items[upper].timestamp - items[lower].timestamp
        guard actualGap > 0 else { return fraction(at: lower) }

        let progress = Double(milliseconds - items[lower].timestamp) / Double(actualGap)
        let displayGap = displayOffsets[upper] - displayOffsets[lower]
        let displayTime = Double(displayOffsets[lower]) + progress * Double(displayGap)
        return displayTime / Double(displayDuration)
    }

    /// The last edit at or before a point on the compressed display clock.
    func index(atFraction fraction: Double) -> Int {
        guard items.count > 1 else { return 0 }

        let clamped = min(max(fraction, 0), 1)
        guard displayDuration > 0 else {
            return Int((clamped * Double(items.count - 1)).rounded())
        }

        let target = Int64((clamped * Double(displayDuration)).rounded())
        var low = 0
        var high = items.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if displayOffsets[mid] <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    private func firstItemIndex(after milliseconds: Int64) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if items[mid].timestamp <= milliseconds {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
