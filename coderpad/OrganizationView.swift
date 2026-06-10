//
//  OrganizationView.swift
//  coderpad
//

import SwiftUI

struct OrganizationView: View {
    let client: CoderPadClient
    @State private var organization: Organization?
    @State private var stats: OrganizationStats?
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var userSearch = ""

    var body: some View {
        Group {
            if isLoading && organization == nil {
                ProgressView("Loading organization…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, organization == nil {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PaneTitle(title: "Organization")
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            statTiles
                            if let stats { activitySection(stats) }
                            if let organization { usersSection(organization) }
                        }
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.top, 4)
                        .padding(.bottom, Spacing.paneV)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: client.apiKey) { await reload() }
        .toolbar {
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarCircle(label: organization?.organizationName ?? "?", diameter: 56, tint: .purple)
            VStack(alignment: .leading, spacing: 4) {
                Text(organization?.organizationName ?? "…")
                    .font(.title2.weight(.semibold))
                Text(organization.map { "ID #\($0.id)" } ?? " ")
                    .foregroundStyle(.secondary)
                    .font(.callout.monospaced())
            }
            Spacer()
        }
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            StatTile(title: "Users", value: organization.map { "\($0.userCount ?? $0.users.count)" } ?? "…",
                     systemImage: "person.3.fill", tint: .blue)
            StatTile(title: "Teams", value: organization.map { "\($0.teams.count)" } ?? "…",
                     systemImage: "rectangle.stack.person.crop", tint: .indigo)
            StatTile(title: "Pads (period)", value: stats.map { "\($0.padsCreated)" } ?? "…",
                     systemImage: "doc.text.fill", tint: .teal)
            if let quota {
                if quota.unlimited == true {
                    StatTile(title: "Quota", value: "Unlimited", systemImage: "infinity", tint: .green)
                } else if let used = quota.padsUsed {
                    StatTile(title: "Pads used", value: "\(used)", systemImage: "chart.bar.fill", tint: .orange)
                }
            }
        }
    }

    private func activitySection(_ stats: OrganizationStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Activity Window", systemImage: "calendar")
                if let start = stats.startTime {
                    LabeledRow(label: "From", value: start.formatted(date: .abbreviated, time: .shortened))
                }
                if let end = stats.endTime {
                    LabeledRow(label: "To", value: end.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledRow(label: "Pads created", value: "\(stats.padsCreated)")
                if let q = quota {
                    if let reset = q.quotaReset {
                        LabeledRow(label: "Quota resets", value: reset.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let trial = q.trialExpiresAt {
                        LabeledRow(label: "Trial expires", value: trial.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledRow(label: "Overages", value: q.overagesEnabled == true ? "Enabled" : "Disabled")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usersSection(_ org: Organization) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Users", systemImage: "person.3")
                    Spacer()
                    Text("\(filteredUsers(org).count)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                TextField("Search users…", text: $userSearch)
                    .textFieldStyle(.roundedBorder)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(filteredUsers(org)) { user in
                        Button {
                            NotificationCenter.default.post(name: .sectionRequested, object: AppSection.pads)
                            NotificationCenter.default.post(name: .padsFilterByOwnerRequested, object: user.email)
                        } label: {
                            HStack(spacing: 10) {
                                AvatarCircle(label: user.name ?? user.email, diameter: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name ?? user.email)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color.subtleStroke.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Show pads owned by \(user.name ?? user.email)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filteredUsers(_ org: Organization) -> [OrganizationUser] {
        let lowered = userSearch.lowercased()
        guard !lowered.isEmpty else { return org.users }
        return org.users.filter { ($0.name ?? "").lowercased().contains(lowered) || $0.email.lowercased().contains(lowered) }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let o = client.organization()
            async let s = client.organizationStats()
            async let q = client.quota()
            organization = try await o
            stats = try? await s
            quota = try? await q
        } catch {
            self.error = error
        }
    }
}
