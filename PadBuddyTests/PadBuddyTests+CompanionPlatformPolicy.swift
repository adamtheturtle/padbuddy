import Foundation
@testable import PadBuddy
import Testing

@Suite("Companion platform policy")
struct CompanionPlatformPolicyTests {
    @Test func `companion section labels resolve through localization`() {
        #expect(companionSectionDisplayName("pads") == String(localized: "Pads"))
        #expect(companionSectionDisplayName("QUESTIONS") == String(localized: "Questions"))
    }

    @Test(arguments: [
        CompanionPlatformPolicy.Platform.watchOS,
        CompanionPlatformPolicy.Platform.tvOS
    ])
    func `companion platforms are read-only`(_ platform: CompanionPlatformPolicy.Platform) {
        let policy = CompanionPlatformPolicy.policy(for: platform)
        #expect(policy.browsableSections == ["pads", "questions"])
        #expect(!policy.allowsMutations)
        #expect(!policy.allowsSettings)
    }

    @Test func `page tokens accept documented string and numeric shapes`() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(CompanionPageToken.self, from: Data(#""next""#.utf8)).value == "next")
        #expect(try decoder.decode(CompanionPageToken.self, from: Data("2".utf8)).value == "2")
    }

    @Test func `an invalid page token reports its decoding context`() throws {
        let data = Data("true".utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CompanionPageToken.self, from: data)
        }
        do {
            _ = try JSONDecoder().decode(CompanionPageToken.self, from: data)
            Issue.record("Expected invalid token decoding to fail")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.debugDescription.contains("string or positive integer"))
        } catch {
            Issue.record("Expected a contextual data-corruption error, got \(error)")
        }
    }
}

@Suite("Companion reload timeout")
nonisolated struct CompanionReloadTimeoutTests {
    @Test(.timeLimit(.minutes(1)))
    func `timeout does not wait for a request that ignores cancellation`() async {
        let request = ControlledCompanionRequest()

        await #expect(throws: URLError.self) {
            try await companionReloadWithTimeout(.milliseconds(20)) {
                await request.wait()
            }
        }

        // The operation can finish only after the timeout has already returned.
        await request.release()
    }
}

private actor ControlledCompanionRequest {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        guard !released else { return }

        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
