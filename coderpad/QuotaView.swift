//
//  QuotaView.swift
//  coderpad
//

import SwiftUI

struct QuotaView: View {
    let client: CoderPadClient
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading && quota == nil {
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
                        .padding(.horizontal, 22)
                        .padding(.top, 4)
                        .padding(.bottom, 22)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task(id: client.apiKey) { await reload() }
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

    @ViewBuilder
    private func statTiles(_ q: Quota) -> some View {
        HStack(spacing: 12) {
            if q.unlimited == true {
                StatTile(title: "Plan", value: "Unlimited", systemImage: "infinity", tint: .green)
            } else if let used = q.padsUsed {
                StatTile(title: "Pads used", value: "\(used)", systemImage: "chart.bar.fill", tint: .blue)
            }
            StatTile(title: "Overages",
                     value: q.overagesEnabled == true ? "Enabled" : "Disabled",
                     systemImage: "arrow.up.right.circle",
                     tint: q.overagesEnabled == true ? .green : .orange)
            if let reset = q.quotaReset {
                StatTile(title: "Resets", value: reset.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "arrow.counterclockwise", tint: .teal)
            }
        }
    }

    private func detailsCard(_ q: Quota) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Details", systemImage: "list.bullet")
                if let used = q.padsUsed {
                    LabeledRow(label: "Pads used", value: "\(used)")
                }
                LabeledRow(label: "Unlimited", value: q.unlimited == true ? "Yes" : "No")
                LabeledRow(label: "Overages", value: q.overagesEnabled == true ? "Enabled" : "Disabled")
                if let reset = q.quotaReset {
                    LabeledRow(label: "Quota resets", value: reset.formatted(date: .abbreviated, time: .shortened))
                }
                if let trial = q.trialExpiresAt {
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
            quota = try await client.quota()
        } catch {
            self.error = error
        }
    }
}
