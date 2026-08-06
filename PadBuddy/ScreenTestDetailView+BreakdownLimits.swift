//
//  ScreenTestDetailView+BreakdownLimits.swift
//  coderpad
//

import SwiftUI

enum ScreenBreakdownLimits {
    static let technologies = 25
    static let skillsPerTechnology = 25
}

func visibleScreenBreakdownNames(_ values: [String: some Any], limit: Int) -> [String] {
    Array(values.keys.sorted().prefix(limit))
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
                            Text(name).font(.callout.weight(.medium))
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
                                    Text(skill).font(.caption).foregroundStyle(.secondary)
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
