# Question renderer comparison

Retain `MacQuestionTable` for account and merged question lists. The existing
FastList hosted-row implementation exceeds the scroll/layout budget in both
fixtures. No renderer migration or public FastList API extension is needed.

## Reproduce

Run on an otherwise idle Mac:

```sh
xcodebuild test -project PadBuddy.xcodeproj -scheme PadBuddy \
  -testPlan QuestionBenchmark -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO -resultBundlePath question-benchmark.xcresult
xcrun xcresulttool export attachments --path question-benchmark.xcresult \
  --output-path question-benchmark-attachments
xcrun xcresulttool get test-results metrics --path question-benchmark.xcresult
```

The opt-in plan compares the actual `MacQuestionTable` and FastList with
`QuestionRowHostableContent`, using 5,000 deterministic questions. The account
case omits account rails; the merged case distributes rows across five account
rails. Titles, languages, draft state, selection, favorites, viewport, and scroll
positions are equivalent. No accounts, credentials, or network are used.

Each scenario creates a 420 by 700-point window outside the visible desktop,
scrolls to 100 positions in steps of 50 rows, forces layout/display, selects the
last row, and changes its favorite state. XCTest runs one warm-up and three
measured iterations. JSON attachments include all four; the table below reports
medians of the three measured iterations. XCTest also records process CPU and
physical memory metrics in the result bundle.

## Recorded result: 2026-10-29

Hardware: Mac17,2, arm64. macOS 27.2 (26B123), Xcode 27.1, Debug configuration.
Dependencies: buddy-kit 0.19.1 and CoderPadKit 0.6.2. All four benchmark tests passed.
The [raw measurements](benchmarks/question-renderers-2026-10-29.json) retain the
per-iteration samples and process metrics.

| Surface | Renderer | Construct ms | Scroll/layout p95 ms | Selection ms | Favorite update ms | Live hosting views | Process CPU s |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Account | Native | 29.93 | 11.21 | 2.60 | 21.02 | 1 | 1.11 |
| Account | Hosted | 128.57 | 37.91 | 10.07 | 9.71 | 16 | 2.82 |
| Merged | Native | 33.34 | 11.97 | 2.61 | 21.15 | 1 | 1.16 |
| Merged | Hosted | 125.54 | 36.09 | 9.91 | 9.99 | 16 | 3.03 |

Hosted rows improve the favorite-state update probe, but take about three times
as long for the scroll/layout probe and more than twice the process CPU time.
Median physical-memory growth was 18.5 MB / 13.4 MB for hosted account / merged
runs, versus approximately 0.77 MB / 0.75 MB for native runs. Process peak memory
is also recorded, but is cumulative across tests and unsuitable for ranking the
renderers in this shared test host.

## Reassessment gate and limits

For reassessment, require hosted scroll/layout p95 at or below 16.7 ms in both
fixtures and no regression larger than both 20 percent and 1 ms against native
rows on the same machine. This is a proposed engineering gate, not a universal
hardware performance guarantee. The current result fails the gate by a wide
margin, so retain native rows.

This synchronous offscreen probe measures main-actor scroll/layout work; it does
not measure displayed frame rate or compositor hitches. CPU metrics cover the
process, not exclusively the main thread. Live hosting-view count and physical
memory growth are proxies, not allocation-churn measurements. Selection and
favorite timings measure state-to-layout updates, not physical mouse latency.

A future candidate that passes the performance gate must also be checked with
Instruments on a visible window, including allocation churn and frame pacing,
and pass interaction parity before migration: dynamic row sizing, account rails,
hover, accessibility labels/values/actions, swipe actions, context menus,
dragging, Return, and scroll restoration. This benchmark does not certify those
interactions for the experimental hosted surface. Existing native behavior stays
in place while that surface fails the performance gate.
