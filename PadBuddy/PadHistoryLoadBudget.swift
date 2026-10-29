import Foundation

struct PadHistoryRequestSelection {
    let requests: [PadHistoryRequest]
    let wasTruncated: Bool
}

nonisolated struct PadHistoryLoadBudget {
    static let maximumFiles = 16
    static let maximumBytes = 64_000_000
    private let byteLimit: Int
    private var retainedBytes = 0
    private var retainedFiles = 0

    init(byteLimit: Int = Self.maximumBytes) {
        self.byteLimit = min(max(0, byteLimit), Self.maximumBytes)
    }

    mutating func admit(_ file: PadFileHistory) -> Bool {
        guard retainedFiles < Self.maximumFiles,
              file.retainedHistoryBytes <= byteLimit - retainedBytes else { return false }

        retainedBytes += file.retainedHistoryBytes
        retainedFiles += 1
        return true
    }
}
