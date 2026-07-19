//
//  MergedQuotaView.swift
//  coderpad
//
//  The combined "All Accounts" Quota section. Unlike pads and questions, quota is
//  inherently per-org: billing cycles, resets, trials, and limits differ between
//  accounts, so a single summed number wouldn't map to any real plan. This view
//  therefore stacks one quota card per account rather than aggregating — giving the
//  honest cross-account picture while keeping every number tied to its own plan.
//
//  Fans out a `quota()` fetch across every account concurrently (mirroring
//  `MergedPadsView`), seeding from `QuotaCacheStore` for an instant first paint and
//  recording each account's error in isolation.
//

import MacPullToRefresh
import SwiftUI

struct MergedQuotaView: View {
    @State private var accounts = AccountsStore.shared
    @State private var cache = QuotaCacheStore.shared
    /// The latest quota per account, seeded from cache then replaced as the
    /// fan-out fetch lands.
    @State private var quotaByAccount: [UUID: Quota] = [:]
    /// The most recent fetch error per account, so one account failing surfaces a
    /// quiet note in its own card without blanking the others.
    @State private var accountErrors: [UUID: String] = [:]
    @State private var isLoading = false
    /// Claim ticket for the newest reload, so an older overlapping fan-out can't
    /// publish over fresher quota or error state (#2393).
    @State private var reloadGeneration = 0
    /// Cross-platform Settings opener (macOS window / iPad sheet), so the
    /// no-accounts state can offer a route to add one (#2399).
    @Environment(\.openAppSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(accounts.mergeableAccounts) { account in
                    accountSection(account)
                }
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.top, Spacing.paneV)
            .padding(.bottom, Spacing.paneV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            // Without this the pane is simply blank, which reads as still-loading
            // rather than "there is nothing to show and here's what to do" (#2399).
            // Matches the merged pad and question lists' empty states (#618).
            if accounts.mergeableAccounts.isEmpty {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Add a CoderPad account to see its plan usage here.")
                } actions: {
                    Button("Open Settings") { openSettings() }
                }
            }
        }
        .macPullToRefresh { await reload() }
        .task(id: accountKey) {
            seedFromCache()
            await reload()
        }
        .onReloadRequest { await reload() }
        .toolbar(id: "merged-quota") {
            // Hidden by default — reachable via View ▸ Customize Toolbar… or the
            // File ▸ Reload command (⌘R) (#413).
            ToolbarItem(id: "reload", placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            .defaultCustomization(.hidden)
        }
    }

    /// One account's quota: an identifying header followed by its full quota
    /// presentation, or a quiet note while it loads, errors, or has no key. The
    /// content is laid out flat (not inside an outer card) because the tiles and
    /// detail sections are themselves cards — nesting would double the chrome.
    private func accountSection(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AccountSectionHeader(account: account)
            // The keyless branch comes first so a quota card left over from before
            // the key was removed can never win over the "no API key" note (#1031).
            if account.apiKey.isEmpty {
                Text("No API key for this account.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let quota = quotaByAccount[account.id] {
                // A recorded refresh failure must stay visible even while cached
                // numbers are shown, or stale usage poses as current (#800).
                if let error = accountErrors[account.id] {
                    StaleRefreshBanner(message: error) { Task { await reload() } }
                }
                QuotaDetail(quota: quota)
            } else if let error = accountErrors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading

    /// A token covering the set of accounts being merged (ids, keys, and endpoints),
    /// so the load task restarts when an account is added, removed, rekeyed, or its
    /// Server URL changes - matching `MergedPadsView.accountKey`. Encoding only key
    /// presence missed non-empty rekeys and endpoint edits, leaving a stale or
    /// wrong-org quota card painting as current (#993/#1031).
    ///
    /// Built from the values themselves rather than a joined string signature. This
    /// feeds `.task(id:)`, which SwiftUI re-evaluates on every body pass, so the
    /// previous form trimmed a key, serialized a URL, byte-counted each field, and
    /// joined the lot once per account per render — all to detect a change (#2281).
    /// Comparing the parts directly is free to build and just as precise.
    private var accountKey: [MergedAccountToken] {
        accounts.mergeableAccounts.map(MergedAccountToken.init(account:))
    }

    /// Drops the in-memory entries for accounts that can no longer have a card:
    /// those whose key was removed, so a card cached before the removal can't
    /// outlive the "No API key" note (#1031), and those that are no longer
    /// mergeable at all.
    ///
    /// Only the keyless case was handled, so an account *removed* from the store
    /// left its quota and error behind — invisible, but able to reappear under a
    /// reused id and outliving the account it described (#2396).
    private func clearStaleEntries() {
        let live = Set(accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }.map(\.id))
        quotaByAccount = quotaByAccount.filter { live.contains($0.key) }
        accountErrors = accountErrors.filter { live.contains($0.key) }
    }

    private func seedFromCache() {
        clearStaleEntries()
        for account in accounts.mergeableAccounts
            where quotaByAccount[account.id] == nil && !account.apiKey.isEmpty {
            quotaByAccount[account.id] = cache.get(account.id)
        }
    }

    /// Fan out a fresh quota fetch across every account concurrently, applying each
    /// result as it lands and recording one account's failure without disturbing
    /// the others.
    /// How many accounts one reload fetches at a time, so a large account set
    /// doesn't open one connection per account at once and delay the visible
    /// cards behind the whole fan-out (#2394).
    private static let reloadWidth = 4

    private func reload() async {
        clearStaleEntries()
        // De-duplicated by id: a duplicated persisted account record used to trap
        // the `uniqueKeysWithValues` map below (#2395).
        var seen = Set<UUID>()
        let mergeable = accounts.mergeableAccounts
            .filter { !$0.apiKey.isEmpty && seen.insert($0.id).inserted }
        guard !mergeable.isEmpty else { return }

        // Claim this reload. Pull-to-refresh, the toolbar button, and the task
        // restart can all run at once, and an older response finishing last used to
        // overwrite the newer quota and error state (#2393).
        reloadGeneration &+= 1
        let generation = reloadGeneration
        isLoading = true
        defer { if generation == reloadGeneration { isLoading = false } }
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        accountErrors.merge(NavigationPrefetchHealth.snapshot(kind: .quota)) { current, _ in current }
        let clientsByID = Dictionary(targets.map { ($0.id, $0.client) }, uniquingKeysWith: { first, _ in first })
        await withTaskGroup(of: (UUID, Quota?, String?).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    do {
                        let quota = try await target.client.quota()
                        return (target.id, quota, nil)
                    } catch {
                        return (target.id, nil, error.localizedDescription)
                    }
                }
            }
            for _ in 0 ..< Self.reloadWidth {
                addNext()
            }
            for await (id, quota, errorText) in group {
                addNext()
                guard generation == reloadGeneration else { continue }

                if let quota {
                    quotaByAccount[id] = quota
                    accountErrors[id] = nil
                    NavigationPrefetchHealth.clear(account: id, kind: .quota)
                    if let client = clientsByID[id] {
                        cache.set(id, quota: quota, via: client)
                    }
                } else {
                    accountErrors[id] = errorText
                }
            }
        }
    }
}

/// The per-account quota presentation — stat tiles, the pace indicator, and the
/// details list — shared by the combined view's per-account cards. Mirrors the
/// body of `QuotaView`; that single-account view keeps its own copy for now, and
/// this is the shared component the two would unify into.
struct QuotaDetail: View {
    let quota: Quota
    /// Computed when the quota changes, not inside `body`. Building it runs Calendar
    /// date arithmetic against a freshly sampled `Date()`, and the combined view draws
    /// one of these per account — so every redraw repeated that work for every card,
    /// against a slightly different "now" each time (#2279).
    @State private var pace: QuotaPace?
    /// Sampled alongside the pace, so the trial card and the pace agree on when "now"
    /// is instead of each reading the clock mid-render.
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statTiles
            if let pace {
                paceCard(pace)
            }
            // Only an active (future) trial is worth surfacing, and as its own card
            // rather than a Details row — matching the single-account Quota view. An
            // expired trial's end date is noise, so it's omitted entirely.
            if let trial = quota.trialExpiresAt, trial > now {
                trialCard(trial)
            }
        }
        .task(id: quota) { refreshPace() }
    }

    private func refreshPace() {
        let sampled = Date()
        now = sampled
        pace = QuotaPace(quota: quota, now: sampled)
    }

    private var statTiles: some View {
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

    /// Highlights an active trial and when it ends. Shown only while the trial is
    /// still in the future; expired trials are omitted (see `body`). Mirrors the
    /// single-account `QuotaView.trialCard`.
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
}

/// The identifying header atop each account's section in the combined Organization
/// and Quota views: the account avatar, its name, and the key owner's email.
struct AccountSectionHeader: View {
    let account: Account

    /// The name to show, falling back when there isn't a usable one.
    ///
    /// Rendering `account.name` directly left a whitespace-only description as an
    /// unlabeled card, which makes cross-account usage impossible to attribute
    /// (#2400). The owner email is the next most identifying thing the header
    /// already has; only when neither exists does it say "Account".
    private var displayName: String {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }

        let email = account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? String(localized: "Account") : email
    }

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(account: account, diameter: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName).font(.headline)
                if !account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   account.userEmail != displayName {
                    Text(account.userEmail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
