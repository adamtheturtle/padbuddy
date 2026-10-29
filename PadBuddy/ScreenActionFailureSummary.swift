import Foundation

/// One dismissible summary, with a fixed diagnostic sample instead of an alert queue.
struct ScreenActionFailureSummary {
    private(set) var samples: [ScreenActionFailure] = []
    private(set) var count = 0
    var isEmpty: Bool {
        samples.isEmpty
    }

    mutating func append(_ failure: ScreenActionFailure) {
        if count < Int.max {
            count += 1
        }
        guard samples.count < 8, !samples.contains(where: {
            $0.testID == failure.testID && $0.operation == failure.operation && $0.accountName == failure.accountName
        }) else { return }

        samples.append(failure)
    }

    mutating func removeAll() {
        samples.removeAll()
        count = 0
    }

    var diagnostic: String {
        var parts: [String] = []
        if count > 1 {
            parts.append(String(localized: "\(count) actions failed.", table: "ScreenActions"))
        }
        parts.append(contentsOf: samples.map(\.detail))
        if count > samples.count {
            parts.append(String(localized: "Only a sample of failures is shown.", table: "ScreenActions"))
        }
        return parts.joined(separator: "\n\n")
    }
}
