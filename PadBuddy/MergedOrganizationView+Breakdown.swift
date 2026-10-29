import SwiftUI

extension MergedOrganizationView {
    func orgBreakdown(_ org: Organization, account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow(label: "Organization", value: ExternalText.singleLine(org.organizationName, limit: 120))
            if let count = OrganizationCountQuality.memberCount(in: org) {
                LabeledRow(label: "Users", value: "\(count)")
            } else {
                LabeledRow(label: "Users", value: String(localized: "Unavailable"))
                Text(OrganizationCountQuality.invalidMemberCountMessage)
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledRow(label: "Teams", value: "\(org.teams.count)")
            if let stats = statsByAccount[account.id] {
                LabeledRow(label: "Pads", value: "\(stats.padsCreated)")
            }
            if let sso = org.singleSignOnSupported {
                LabeledRow(label: "Single sign-on",
                           value: sso ? String(localized: "Enabled") : String(localized: "Disabled"))
            }
        }
    }
}
