//
//  QuotaView.swift
//  coderpad
//

import MacPullToRefresh
import SwiftUI

struct QuotaView: View {
    let client: CoderPadClient
    /// The account this view shows, captured by the caller: quota responses are
    /// displayed and cached strictly under this id, never under whatever account
    /// is current when a slow response lands (#797).
    let accountID: UUID?
    @State private var cache = QuotaCacheStore.shared
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var error: (any Error)?
    /// Recomputed when the quota changes rather than in `body`: building it runs
    /// Calendar date arithmetic against a freshly sampled `Date()`, which every
    /// redraw repeated (#2279). `now` is sampled alongside it so the trial card and
    /// the pace agree on when "now" is.
    @State private var pace: QuotaPace?
    @State private var now = Date()

    var body: some View {
        Group {
            if isLoading, quota == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, quota == nil {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // A failed refresh over previously loaded numbers must not
                        // pose as current data (#800).
                        if let error {
                            StaleRefreshBanner(message: error.localizedDescription) {
                                Task { await reload() }
                            }
                        }
                        if let quota {
                            statTiles(quota)
                            if let pace {
                                paceCard(pace)
                            }
                            if let trial = quota.trialExpiresAt, trial > now {
                                trialCard(trial)
                            }
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
        .task(id: quota) {
            let sampled = Date()
            now = sampled
            pace = quota.flatMap { QuotaPace(quota: $0, now: sampled) }
        }
        .task(id: client.taskIdentity) {
            // Show the last-loaded quota immediately so re-entering the section
            // doesn't flash a spinner; the reload below refreshes it in place.
            if quota == nil, let id = accountID {
                quota = cache.get(id)
            }
            await reload()
        }
        .onReloadRequest { await reload() }
        .toolbar(id: "quota") {
            // Hidden by default — reachable via View ▸ Customize Toolbar… or the
            // File ▸ Reload command (⌘R) (#413).
            ToolbarItem(id: "reload", placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            .defaultCustomization(.hidden)
        }
    }

    private func statTiles(_ quota: Quota) -> some View {
        // Adaptive grid so the tiles stay on one row in a wide (macOS) pane but
        // wrap to multiple columns in a narrow one (e.g. iPad mini portrait),
        // keeping each tile wide enough that its uppercase title never hyphenates.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
            if quota.unlimited == true {
                StatTile(title: "Plan", value: String(localized: "Unlimited"), systemImage: "infinity", tint: .green)
            } else if let used = quota.padsUsed {
                StatTile(title: "Pads used", value: "\(used)", systemImage: "chart.bar.fill", tint: .blue)
            }
            if quota.unlimited != true, let remaining = quota.padsRemaining {
                StatTile(title: "Remaining", value: "\(remaining)",
                         systemImage: "tray.fill",
                         tint: remaining <= 0 ? .red : .green)
            }
            StatTile(title: "Overages",
                     value: quota.overagesEnabled == true
                         ? String(localized: "Enabled")
                         : String(localized: "Disabled"),
                     systemImage: "arrow.up.right.circle",
                     tint: quota.overagesEnabled == true ? .green : .orange)
            if let reset = quota.quotaReset {
                StatTile(title: "Resets", value: reset.formatted(SharedDateStyles.longDate),
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
                        // Decorative: the headline beside it states the pace, and the
                        // usage bar carries its own accessibility value.
                        .accessibilityHidden(true)
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

    /// Highlights an active trial and when it ends. Only shown while the trial
    /// is still in the future; expired trials are omitted entirely.
    private func trialCard(_ expiresAt: Date) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Trial", systemImage: "clock.badge.checkmark")
                Text("Your trial expires \(expiresAt.formatted(SharedDateStyles.longDateAndTime)).")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            if let id = accountID {
                cache.set(id, quota: fetched, via: client)
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
        fractionUsed = Double(used) / Double(limit)
        // Divide by elapsed time to project the full cycle; guard against the
        // very start of the cycle where a tiny denominator blows up.
        //
        // No arbitrary ceiling. Clamping to 9,999 understated any organization whose
        // plan is larger than that — and because `status` compares the projection
        // against the limit, a plan of 20,000 heading for 30,000 read back as
        // "on track to stay within your limit" (#2391). The 0.02 floor above already
        // bounds the projection at 50x what has actually been used, so a tiny
        // denominator can't produce a runaway figure.
        let projected = fractionElapsed > 0.02 ? Double(used) / fractionElapsed : Double(used)
        projectedUsage = max(used, Int(projected.rounded()))
    }

    var headline: String {
        switch status {
        case .over: String(localized: "Over your limit for this cycle")
        case .trendingOver: String(localized: "On track to exceed your limit")
        case .onTrack: String(localized: "On track to stay within your limit")
        }
    }

    var accessibilityLabel: String {
        let percent = fractionElapsed.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(used) of \(limit) pads used, \(percent) through the cycle. \(headline).")
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
