import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Interview analytics")
struct InterviewAnalyticsTests {
    @Test
    func `transcript availability distinguishes absence emptiness and unavailable source`() throws {
        for (fields, expected) in [
            ([:], PadTranscriptAvailability.notProvided),
            (["transcript": []], .empty),
            (["transcript": [], "transcript_source_unavailable": true], .unavailable)
        ] as [([String: Any], PadTranscriptAvailability)] {
            #expect(try PadTranscriptAvailability(pad(fields)) == expected)
        }
        let value = try pad(["transcript": [["id": "spoken", "kind": "transcript", "text": "Hello", "timestamp": 1]]])
        #expect(PadTranscriptAvailability(value) == .available)
    }

    @Test
    func `structured outlines preserve false zero order and explicit nulls with bounded disclosure`() {
        let rows = StructuredContentRows(.object(["completed": .bool(false), "sections": .array([
            .object(["title": .string("Boundary cases"), "start_ms": .number(0)]), .null
        ])]))
        #expect(rows.truncated == false)
        #expect(rows.rows.map(\.text) == [String(localized: "No"), "", "", "0", "Boundary cases",
                                          String(localized: "Not provided")])
        let oversized = StructuredContentRows(.array((0 ..< 300).map { .number(Decimal($0)) }))
        #expect(oversized.rows.count == 200)
        #expect(oversized.truncated == true)
        let long = StructuredContentRows(.string(String(repeating: "a", count: 9000)))
        #expect(long.rows.map(\.text) == [String(repeating: "a", count: 8192)])
        #expect(long.truncated == true)
    }

    @Test @MainActor
    func `detail-only analytics load independently of editor history and clear across identities`() async {
        let client = CoderPadClient.mock(key: "analytics-model-" + UUID().uuidString)
        let model = PadAnalyticsModel()
        let first = PadDetailLoadIdentity(padID: "DEMOXYZ2", accountID: UUID(), clientIdentity: client.taskIdentity)
        await model.load(client: client, identity: first)
        #expect(model.error == nil)
        #expect(model.loading == false)
        #expect(model.pad?.interviewHighlights == "The candidate explained pagination and boundary cases.")
        #expect(model.pad?.transcript?.map(\.kind) == [.transcript, .systemMessage])
        #expect(model.pad?.transcript?.map(\.timestamp) == [1_780_680_000_000, 1_780_680_002_000])
        let second = PadDetailLoadIdentity(padID: "DEMOSWFT5", accountID: UUID(), clientIdentity: client.taskIdentity)
        await model.load(client: client, identity: second)
        #expect(model.identity == second)
        #expect(model.pad?.interviewHighlights == nil)
        #expect(model.pad?.transcriptSourceUnavailable == true)
        #expect(model.pad?.reviewReports?.map(\.status) == ["pending", "error"])
        let missing = PadDetailLoadIdentity(padID: "DOESNOTEXIST", accountID: UUID(),
                                            clientIdentity: client.taskIdentity)
        await model.load(client: client, identity: missing)
        #expect(model.pad == nil)
        #expect(model.error != nil)
    }

    @Test @MainActor
    func `cancelled analytics loads cannot publish a previous pad`() async {
        let client = CoderPadClient.mock(key: "analytics-cancel-" + UUID().uuidString)
        let model = PadAnalyticsModel()
        let identity = PadDetailLoadIdentity(padID: "DEMOXYZ2", accountID: nil, clientIdentity: client.taskIdentity)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(client: client, identity: identity)
        }
        await task.value
        #expect(model.pad == nil)
        #expect(model.error == nil)
    }

    #if os(macOS)
        @Test @MainActor
        func `optional analytics content renders when fields are absent`() throws {
            let value = try pad([:])
            let renderer = ImageRenderer(content: PadAnalyticsContent(pad: value).frame(width: 600))
            let image = try #require(renderer.nsImage)
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    #endif

    private func pad(_ fields: [String: Any]) throws -> Pad {
        var body: [String: Any] = ["id": "ANALYTICS", "title": "Interview", "state": "ended", "language": "python3"]
        body.merge(fields) { _, new in new }
        return try CoderPadClient.decoder.decode(Pad.self, from: JSONSerialization.data(withJSONObject: body))
    }
}
