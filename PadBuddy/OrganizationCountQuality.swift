import Foundation

nonisolated enum OrganizationCountQuality {
    /// Match the supported count range already used for quota values.
    static let maximumCount = 1_000_000_000

    static func isSupported(_ count: Int) -> Bool {
        (0 ... maximumCount).contains(count)
    }

    static func validatedStats(_ stats: OrganizationStats?) -> OrganizationStats? {
        guard let stats, isSupported(stats.padsCreated) else { return nil }

        return stats
    }

    static var invalidStatsMessage: String {
        String(localized: "The pad statistics are outside the supported range.", table: "OrganizationDataQuality")
    }
}
