import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad-wide history loading budgets")
struct PadHistoryLoadBudgetTests {
    @Test @MainActor func `history requests stop at the shared pad file limit`() throws {
        let files = (0 ... PadHistoryLoadBudget.maximumFiles).map { index in
            ["path": "file-\(index).py", "contents": "x",
             "history": "https://app.coderpad.io/history/file-\(index)"]
        }
        let data = try JSONSerialization.data(withJSONObject: ["id": 1, "file_contents": files])
        let environment = try CoderPadClient.decoder.decode(PadEnvironment.self, from: data)
        let view = PadDetailView(
            client: CoderPadClient.mock(key: "history-file-budget"), pad: Pad(id: "ABC123", title: "Pad")
        )
        let selection = view.historyRequestSelection(for: [environment])
        #expect(selection.requests.count == PadHistoryLoadBudget.maximumFiles)
        #expect(selection.wasTruncated)
    }

    @Test func `retained files share one byte budget`() {
        let file = PadFileHistory(id: "f", title: "main", language: nil, history: PadHistory(entries: [
            PadHistoryEntry(id: "e", author: "Ada", operations: [.insert("code")], timestamp: 1)
        ]))
        var budget = PadHistoryLoadBudget(byteLimit: file.retainedHistoryBytes)
        let admittedFirst = budget.admit(file)
        let admittedSecond = budget.admit(file)
        #expect(admittedFirst)
        #expect(!admittedSecond)
    }
}
