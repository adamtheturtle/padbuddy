#if os(macOS)
    import AppKit
    import Darwin
    @testable import PadBuddy
    import SwiftUI
    import XCTest

    final nonisolated class QuestionRendererBenchmarkTests: XCTestCase {
        @MainActor func testNativeAccount() throws {
            try benchmark(native: true, merged: false)
        }

        @MainActor func testHostedAccount() throws {
            try benchmark(native: false, merged: false)
        }

        @MainActor func testNativeMerged() throws {
            try benchmark(native: true, merged: true)
        }

        @MainActor func testHostedMerged() throws {
            try benchmark(native: false, merged: true)
        }

        @MainActor
        private func benchmark(native: Bool, merged: Bool) throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_QUESTION_BENCHMARKS"] == "1")
            let rows = try QuestionBenchmarkRow.fixtures(merged: merged)
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            var reports: [[String: Any]] = []
            measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
                autoreleasepool {
                    reports.append(runScenario(native: native, rows: rows))
                }
            }
            let report: [String: Any] = [
                "renderer": native ? "native" : "hosted", "merged": merged, "rows": rows.count,
                "hardware": hardwareModel(), "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "configuration": "Debug", "iterations": reports
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: .sortedKeys)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "question-benchmark-\(native ? "native" : "hosted")-\(merged ? "merged" : "account")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        @MainActor
        private func runScenario(native: Bool, rows: [QuestionBenchmarkRow]) -> [String: Any] {
            let state = QuestionBenchmarkState()
            let began = ContinuousClock.now
            let surface = QuestionBenchmarkSurface(native: native, rows: rows, state: state)
            let host = NSHostingView(rootView: surface)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 420, height: 700),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            let construction = milliseconds(since: began)
            guard let table: NSTableView = descendant(in: host) else {
                XCTFail("The actual renderer must create its table")
                return [:]
            }

            XCTAssertEqual(table.numberOfRows, rows.count)
            var scrollTimes: [Double] = []
            for index in stride(from: 0, to: rows.count, by: 50) {
                let start = ContinuousClock.now
                table.scrollRowToVisible(index)
                host.layoutSubtreeIfNeeded()
                table.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                scrollTimes.append(milliseconds(since: start))
            }
            let selectionStart = ContinuousClock.now
            table.selectRowIndexes(IndexSet(integer: rows.count - 1), byExtendingSelection: false)
            host.layoutSubtreeIfNeeded()
            let selection = milliseconds(since: selectionStart)
            let favoriteStart = ContinuousClock.now
            state.favorites.insert(rows[rows.count - 1].id)
            host.layoutSubtreeIfNeeded()
            let favorite = milliseconds(since: favoriteStart)
            return ["constructionMilliseconds": construction,
                    "scrollLayoutP95Milliseconds": percentile95(scrollTimes),
                    "selectionUpdateMilliseconds": selection, "favoriteUpdateMilliseconds": favorite,
                    "finalLiveHostingViews": hostingViewCount(host)]
        }

        private func milliseconds(since start: ContinuousClock.Instant) -> Double {
            let duration = start.duration(to: .now).components
            return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        }

        private func percentile95(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[(sorted.count - 1) * 95 / 100]
        }

        @MainActor
        private func descendant<ViewType: NSView>(in view: NSView) -> ViewType? {
            if let result = view as? ViewType {
                return result
            }
            return view.subviews.lazy.compactMap { self.descendant(in: $0) as ViewType? }.first
        }

        @MainActor
        private func hostingViewCount(_ view: NSView) -> Int {
            let count = String(describing: type(of: view)).contains("HostingView") ? 1 : 0
            return count + view.subviews.reduce(0) { $0 + hostingViewCount($1) }
        }

        private func hardwareModel() -> String {
            var size = 0
            guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0 else { return "Unknown" }

            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Unknown" }

            return String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "Unknown"
        }
    }
#endif
