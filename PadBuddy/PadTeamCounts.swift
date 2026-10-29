import Foundation

enum PadTeamCounts {
    static func counts(in pads: some Sequence<Pad>, teams: [String]) -> [String: Int] {
        let wanted = Set(teams.prefix(FilterOptionValues.maximumOptions).compactMap(key))
        guard !wanted.isEmpty else { return [:] }

        var result: [String: Int] = [:]
        for pad in pads {
            guard let key = key(pad.team?.name), wanted.contains(key) else { continue }

            result[key, default: 0] += 1
        }
        return result
    }

    static func count(for team: String, in counts: [String: Int]) -> Int {
        guard let key = key(team) else { return 0 }

        return counts[key, default: 0]
    }

    private static func key(_ team: String?) -> String? {
        FilterOptionValues.boundedTeam(team)?.folding(options: .caseInsensitive, locale: nil)
    }
}
