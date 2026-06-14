//
//  QuotaView.swift
//  coderpad
//

import SwiftUI

struct QuotaView: View {
    let client: CoderPadClient
    @State private var accounts = AccountsStore.shared
    @State private var cache = QuotaCacheStore.shared
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var error: Error?
    /// The header gauge glyph's point size, scaled with the user's preferred text
    /// size (tracking Large Title) so it grows with the accessibility setting
    /// rather than staying fixed.
    @ScaledMetric(relativeTo: .largeTitle) private var gaugeGlyphSize: CGFloat = 36

    var body: some View {
        Group {
            if isLoading, quota == nil {
                ProgressView("Loading quota…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, quota == nil {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if let quota {
                            statTiles(quota)
                            if let pace = QuotaPace(quota: quota, now: Date()) {
                                paceCard(pace)
                            }
                            detailsCard(quota)
                        }
                    }
                    .padding(.horizontal, Spacing.paneH)
                    .padding(.top, Spacing.paneV)
                    .padding(.bottom, Spacing.paneV)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .macPullToRefresh { await reload() }
            }
        }
        .task(id: client.apiKey) {
            // Show the last-loaded quota immediately so re-entering the section
            // doesn't flash a spinner; the reload below refreshes it in place.
            if quota == nil, let id = accounts.currentAccountID {
                quota = cache.get(id)
            }
            await reload()
        }
        .task {
            for await _ in AppRouter.reloads {
                await reload()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: gaugeGlyphSize))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan & Quota").font(.title2.weight(.semibold))
                Text("Usage and limits on your CoderPad subscription.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func statTiles(_ quota: Quota) -> some View {
        HStack(spacing: 12) {
            if quota.unlimited == true {
                StatTile(title: "Plan", value: "Unlimited", systemImage: "infinity", tint: .green)
            } else if let used = quota.padsUsed {
                StatTile(title: "Pads used", value: "\(used)", systemImage: "chart.bar.fill", tint: .blue)
            }
            if quota.unlimited != true, let remaining = quota.padsRemaining {
                StatTile(title: "Remaining", value: "\(remaining)",
                         systemImage: "tray.fill",
                         tint: remaining <= 0 ? .red : .green)
            }
            StatTile(title: "Overages",
                     value: quota.overagesEnabled == true ? "Enabled" : "Disabled",
                     systemImage: "arrow.up.right.circle",
                     tint: quota.overagesEnabled == true ? .green : .orange)
            if let reset = quota.quotaReset {
                StatTile(title: "Resets", value: reset.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "arrow.counterclockwise", tint: .teal)
            }
        }
    }

    /// Visualizes whether pad usage is trending over the billing-cycle limit by
    /// comparing how much quota is spent against how far the cycle has elapsed.
    private func paceCard(_ pace: QuotaPace) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Pace", systemImage: "speedometer")
                HStack(spacing: 8) {
                    Image(systemName: pace.status.systemImage)
                        .foregroundStyle(pace.status.tint)
                    Text(pace.headline).font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                }
                usageBar(pace)
                HStack {
                    Text("\(pace.used) of \(pace.limit) pads used")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("Projected ~\(pace.projectedUsage) by reset")
                        .foregroundStyle(pace.status.tint)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A usage bar filled to `fractionUsed`, with a vertical marker at
    /// `fractionElapsed` — where usage would be if it tracked the cycle exactly.
    /// Fill past the marker means usage is running ahead of the calendar.
    private func usageBar(_ pace: QuotaPace) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usedWidth = min(1, pace.fractionUsed) * width
            let paceX = min(1, pace.fractionElapsed) * width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(pace.status.tint.opacity(0.85))
                    .frame(width: usedWidth)
                Rectangle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 2)
                    .offset(x: max(0, paceX - 1))
            }
        }
        .frame(height: 10)
        .help("The marker shows where your usage would be if it tracked the billing cycle evenly.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pace.accessibilityLabel)
    }

    private func detailsCard(_ quota: Quota) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Details", systemImage: "list.bullet")
                if let used = quota.padsUsed {
                    LabeledRow(label: "Pads used", value: "\(used)")
                }
                if quota.unlimited != true, let limit = quota.billingCyclePadLimit {
                    LabeledRow(label: "Billing cycle limit", value: "\(limit)")
                }
                if let trial = quota.trialExpiresAt {
                    LabeledRow(label: "Trial expires", value: trial.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await client.quota()
            quota = fetched
            if let id = accounts.currentAccountID {
                cache.set(id, quota: fetched)
            }
        } catch {
            self.error = error
        }
    }
}

/// Derives whether pad usage is on track to exceed the billing-cycle limit, by
/// comparing the fraction of quota spent against the fraction of the cycle that
/// has elapsed. The cycle start isn't returned by the API, so it's estimated as
/// one month before the reset date (CoderPad quotas reset monthly).
nonisolated struct QuotaPace {
    let used: Int
    let limit: Int
    /// Share of the quota consumed (0...1+, can exceed 1 once over).
    let fractionUsed: Double
    /// Share of the billing cycle elapsed (0...1).
    let fractionElapsed: Double
    /// Usage extrapolated to the end of the cycle at the current pace.
    let projectedUsage: Int

    enum Status { case over, trendingOver, onTrack }

    var status: Status {
        if used >= limit { return .over }
        return projectedUsage > limit ? .trendingOver : .onTrack
    }

    init?(quota: Quota, now: Date) {
        guard quota.unlimited != true,
              let used = quota.padsUsed,
              let limit = quota.billingCyclePadLimit, limit > 0,
              let reset = quota.quotaReset else { return nil }

        let calendar = Calendar.current
        let cycleStart = calendar.date(byAdding: .month, value: -1, to: reset) ?? reset
        let total = reset.timeIntervalSince(cycleStart)
        let elapsed = now.timeIntervalSince(cycleStart)
        let fractionElapsed = total > 0 ? min(1, max(0, elapsed / total)) : 1

        self.used = used
        self.limit = limit
        self.fractionElapsed = fractionElapsed
        self.fractionUsed = Double(used) / Double(limit)
        // Divide by elapsed time to project the full cycle; guard against the
        // very start of the cycle where a tiny denominator blows up.
        let projected = fractionElapsed > 0.02 ? Double(used) / fractionElapsed : Double(used)
        self.projectedUsage = min(9999, max(used, Int(projected.rounded())))
    }

    var headline: String {
        switch status {
        case .over: "Over your limit for this cycle"
        case .trendingOver: "On track to exceed your limit"
        case .onTrack: "On track to stay within your limit"
        }
    }

    var accessibilityLabel: String {
        "\(used) of \(limit) pads used, \(Int((fractionElapsed * 100).rounded()))% through the cycle. \(headline)."
    }
}

extension QuotaPace.Status {
    var tint: Color {
        switch self {
        case .over: .red
        case .trendingOver: .orange
        case .onTrack: .green
        }
    }

    var systemImage: String {
        switch self {
        case .over: "exclamationmark.triangle.fill"
        case .trendingOver: "arrow.up.forward.circle.fill"
        case .onTrack: "checkmark.circle.fill"
        }
    }
}
