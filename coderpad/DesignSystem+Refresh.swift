//
//  DesignSystem+Refresh.swift
//  coderpad
//

import Foundation

/// Wall-clock scheduling for ``periodicReload``: works out when the next refresh
/// should fire on a fixed cadence, independent of how long a refresh itself takes.
enum RefreshSchedule {
    /// The next fire instant on a fixed cadence. Advances `last` by `interval`, then
    /// skips any boundaries that have already passed (a refresh ran long, or the app
    /// was inactive between ticks) so the loop realigns to the next *future* boundary
    /// instead of firing a catch-up burst. The result is always strictly after `now`,
    /// so the caller never sleeps for a non-positive duration.
    static func nextFire(after last: ContinuousClock.Instant,
                         interval: Duration,
                         now: ContinuousClock.Instant) -> ContinuousClock.Instant {
        // A non-positive interval would never advance the grid; fall back to a fixed
        // one-second cadence so the loop still makes forward progress.
        guard interval > .zero else { return now.advanced(by: .seconds(1)) }

        var fire = last.advanced(by: interval)
        // Skip boundaries already in the past. Capped so a pathological `last`/`now`
        // gap can never spin here — past the cap we simply schedule one interval out.
        var steps = 0
        while fire <= now, steps < 100_000 {
            fire = fire.advanced(by: interval)
            steps += 1
        }
        return fire > now ? fire : now.advanced(by: interval)
    }
}

// Fixed-interval convenience overload, kept alongside the dynamic-interval one.
// periphery:ignore
/// Runs `work` immediately, then re-runs it on `interval` until the task is cancelled.
/// Cancellation breaks the loop cleanly instead of being swallowed by `try?`.
func periodicReload(interval: Duration, work: () async -> Void) async {
    await periodicReload(interval: { interval }, work: work)
}

/// Variant whose interval is recomputed after each run, letting callers stretch the
/// cadence based on how heavy the last run turned out to be — e.g. a big org with
/// thousands of pads polling far less often than a small one.
///
/// Refreshes fire on a fixed wall-clock grid anchored at the first run, so the time
/// a refresh takes doesn't push the next one out (no cumulative drift), and a long
/// gap realigns to the next boundary rather than triggering a burst (see
/// ``RefreshSchedule``).
func periodicReload(interval: () -> Duration, work: () async -> Void) async {
    let clock = ContinuousClock()
    await work()
    var last = clock.now
    while !Task.isCancelled {
        let fire = RefreshSchedule.nextFire(after: last, interval: interval(), now: clock.now)
        do {
            try await clock.sleep(until: fire, tolerance: nil)
        } catch {
            break
        }
        last = fire
        await work()
    }
}
