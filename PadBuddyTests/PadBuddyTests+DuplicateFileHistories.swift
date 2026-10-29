import Foundation
@testable import PadBuddy
import Testing

@Suite("Duplicate file history selection")
@MainActor
struct DuplicateFileHistoryTests {
    private func file(_ count: Int) -> PadFileHistory {
        PadFileHistory(id: "same", title: "main.py", language: "python", history: PadHistory(entries:
            (0 ..< count).map { index in
                PadHistoryEntry(id: "e\(index)", author: "Ada", operations: [.insert("x")], timestamp: Int64(index))
            }))
    }

    @Test func `a later richer response wins independently of response order`() {
        let older = file(1), newer = file(2)
        let forwards = PadFileHistory.preferredUnique([older, newer])
        let backwards = PadFileHistory.preferredUnique([newer, older])
        #expect(forwards == backwards)
        #expect(forwards.first?.snapshots.count == 2)
    }

    @Test func `view content and timeline use the same selected history`() {
        let view = HistoryPlaybackView(histories: [file(1), file(2)], events: [], dark: false)
        #expect(view.histories.count == 1)
        #expect(view.histories.first?.contents(at: 1) == "xx")
        #expect(view.hasDuplicateHistories)
        let timeline = PadPlaybackTimeline(histories: [file(1), file(2)])
        #expect(timeline.items.count == 2)
    }
}
