//
//  ScreenTestDetailView+BreakdownLimits.swift
//  coderpad
//

import SwiftUI

enum ScreenBreakdownLimits {
    static let technologies = 25
    static let skillsPerTechnology = 25
    /// Names are server strings rendered straight into `Text` and sorted against each
    /// other. Counts were capped but lengths were not, so a response could stay inside the
    /// count limits while carrying a handful of multi-megabyte names — enough to make
    /// sorting and layout unusable (#4578).
    static let nameCharacters = 120
}

/// A display-safe label for one breakdown name: bounded, and with the ellipsis that says
/// the rest was dropped rather than silently showing a truncated name as if it were whole.
func screenBreakdownLabel(_ name: String) -> String {
    guard name.count > ScreenBreakdownLimits.nameCharacters else { return name }

    return String(name.prefix(ScreenBreakdownLimits.nameCharacters)) + "…"
}

/// The names to show, bounded in count and each bounded in length. Sorting happens on the
/// bounded prefixes so an overlong name cannot make the comparison itself expensive.
func visibleScreenBreakdownNames(_ values: [String: some Any], limit: Int) -> [String] {
    values.keys
        .map { (key: $0, sortKey: String($0.prefix(ScreenBreakdownLimits.nameCharacters))) }
        .sorted { ($0.sortKey, $0.key.count) < ($1.sortKey, $1.key.count) }
        .prefix(limit)
        .map(\.key)
}

extension ScreenTestDetailView {
    func technologyBreakdown(_ technologies: [String: ScreenTechnologyResult]) -> some View {
        let visibleNames = visibleScreenBreakdownNames(technologies, limit: ScreenBreakdownLimits.technologies)
        return LazyVStack(alignment: .leading, spacing: 10) {
            Text("By technology")
                .font(.callout.weight(.medium))
            ForEach(visibleNames, id: \.self) { name in
                if let result = technologies[name] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(screenBreakdownLabel(name)).font(.callout.weight(.medium))
                            Spacer(minLength: 0)
                            if let score = result.score {
                                Text(scoreText(score))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        let visibleSkills = visibleScreenBreakdownNames(
                            result.skills, limit: ScreenBreakdownLimits.skillsPerTechnology
                        )
                        ForEach(visibleSkills, id: \.self) { skill in
                            if let value = result.skills[skill] {
                                HStack {
                                    Text(screenBreakdownLabel(skill)).font(.caption).foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    if let score = value.score {
                                        Text(scoreText(score))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, 12)
                            }
                        }
                        if result.skills.count > visibleSkills.count {
                            Text("\(result.skills.count - visibleSkills.count) additional skills omitted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            if technologies.count > visibleNames.count {
                Text("\(technologies.count - visibleNames.count) additional technologies omitted")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
