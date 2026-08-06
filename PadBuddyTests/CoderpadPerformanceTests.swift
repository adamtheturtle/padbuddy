//
//  CoderpadPerformanceTests.swift
//  PadBuddyTests
//
//  Trend-oriented list construction measurements for the nightly Performance plan.
//

#if os(macOS)
    import AppKit
    import FastList
    import SwiftUI
    import XCTest

    final nonisolated class CoderpadPerformanceTests: XCTestCase {
        private struct Row: Identifiable {
            let id: Int
            let title: String
            let subtitle: String
        }

        private static let rows = (0 ..< 5000).map {
            Row(id: $0, title: "Question \($0)", subtitle: "swift • owner-\($0 % 25)")
        }

        private let metrics: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]

        @MainActor
        func testFastListConstruction() {
            measure(metrics: metrics, options: measurementOptions) {
                render(
                    FastList(Self.rows, selection: .constant(Set<Int>())) { row in
                        self.rowView(row)
                    }
                )
            }
        }

        @MainActor
        func testNativeListConstruction() {
            measure(metrics: metrics, options: measurementOptions) {
                render(
                    List(Self.rows, selection: .constant(Set<Int>())) { row in
                        self.rowView(row)
                    }
                )
            }
        }

        @MainActor
        private var measurementOptions: XCTMeasureOptions {
            let options = XCTMeasureOptions()
            options.iterationCount = 5
            return options
        }

        @MainActor
        private func rowView(_ row: Row) -> some View {
            VStack(alignment: .leading) {
                Text(row.title)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @MainActor
        private func render(_ view: some View) {
            autoreleasepool {
                let host = NSHostingView(rootView: view.frame(width: 420, height: 700))
                host.frame = CGRect(x: 0, y: 0, width: 420, height: 700)
                host.layoutSubtreeIfNeeded()
                _ = host.fittingSize
            }
        }
    }
#endif
