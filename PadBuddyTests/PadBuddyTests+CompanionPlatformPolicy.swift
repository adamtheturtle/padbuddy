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
struct CompanionReloadTimeoutTests {
    @Test func `timeout does not wait for a request that ignores cancellation`() async throws {
        let started = ContinuousClock.now

        await #expect(throws: URLError.self) {
            try await companionReloadWithTimeout(.milliseconds(20)) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        continuation.resume(returning: ())
                    }
                }
            }
        }

        #expect(ContinuousClock.now - started < .milliseconds(250))
    }
}
