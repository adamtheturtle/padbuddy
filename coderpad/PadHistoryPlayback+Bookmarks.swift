//
//  PadHistoryPlayback+Bookmarks.swift
//  coderpad
//

import SwiftUI

extension HistoryPlaybackView {
    @ViewBuilder
    var bookmarkButton: some View {
        let timestamp = timeline.items.indices.contains(position) ? timeline.items[position].timestamp : nil
        let isBookmarked = timestamp.map(bookmarkedTimestamps.contains) ?? false
        Button {
            guard let timestamp else { return }

            if isBookmarked {
                bookmarkedTimestamps.remove(timestamp)
            } else {
                bookmarkedTimestamps.insert(timestamp)
            }
            PlaybackPositionStore.saveBookmarks(bookmarkedTimestamps, for: histories)
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .frame(width: 24, height: 24)
        }
        .help(isBookmarked ? "Remove revision bookmark" : "Bookmark this revision")
        .accessibilityLabel(isBookmarked ? "Remove revision bookmark" : "Bookmark this revision")
        .disabled(timestamp == nil)
    }
}
