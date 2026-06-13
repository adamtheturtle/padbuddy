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

    var body: some View {
        Group {
            if isLoading, quota == nil {
                ProgressView("Loading quota…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, quota == nil {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PaneTitle(title: "Quota")
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            if let quota {
                                statTiles(quota)
                                detailsCard(quota)
                            }
                        }
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.top, 4)
                        .padding(.bottom, Spacing.paneV)
                    }
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
            for await _ in NotificationCenter.default.notifications(named: .reloadRequested) {
                await reload()
            }
        }
        .toolbar(id: "quota.toolbar") {
            ToolbarItem(id: "reload") {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 36))
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

    private func detailsCard(_ quota: Quota) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Details", systemImage: "list.bullet")
                if let used = quota.padsUsed {
                    LabeledRow(label: "Pads used", value: "\(used)")
                }
                if quota.unlimited != true, let remaining = quota.padsRemaining {
                    LabeledRow(label: "Pads remaining", value: "\(remaining)")
                }
                if quota.unlimited != true, let limit = quota.billingCyclePadLimit {
                    LabeledRow(label: "Billing cycle limit", value: "\(limit)")
                }
                LabeledRow(label: "Unlimited", value: quota.unlimited == true ? "Yes" : "No")
                LabeledRow(label: "Overages", value: quota.overagesEnabled == true ? "Enabled" : "Disabled")
                if let reset = quota.quotaReset {
                    LabeledRow(label: "Quota resets", value: reset.formatted(date: .abbreviated, time: .shortened))
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
