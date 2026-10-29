@testable import PadBuddy
import SwiftUI
import Testing

@MainActor
struct InterviewKeyOwnerTests {
    private func user(_ name: String?, allowed: Bool = false) throws -> InterviewUser {
        try JSONDecoder().decode(InterviewUser.self, from: JSONSerialization.data(withJSONObject: [
            "name": name as Any? ?? NSNull(), "allow_pad_creation": allowed, "analytics_id": "anonymous-123"
        ]))
    }

    @Test
    func `superseded credentials cannot publish the previous key owner`() async throws {
        let model = InterviewKeyOwnerModel()
        let old = CoderPadClient.mock(key: "previous")
        let current = CoderPadClient.mock(key: "current")
        let previousUser = try user("Previous")
        let currentUser = try user("Current", allowed: true)
        var continuation: CheckedContinuation<InterviewUser, Never>?
        let pending = Task {
            await model.load(client: old) { _ in
                await withCheckedContinuation { continuation = $0 }
            }
        }
        while continuation == nil {
            await Task.yield()
        }
        await model.load(client: current) { _ in currentUser }
        continuation?.resume(returning: previousUser)
        await pending.value
        #expect(model.user == currentUser)
        #expect(model.identity == current.taskIdentity)
        #expect(!model.loading)
    }

    @Test
    func `identity lookup errors can be retried without validating the account`() async throws {
        let model = InterviewKeyOwnerModel()
        let client = CoderPadClient.mock()
        await model.load(client: client) { _ in throw CoderPadError.decode("Unavailable") }
        #expect(model.error != nil)
        #expect(model.user == nil)
        let result = try user(nil)
        await model.load(client: client) { _ in result }
        #expect(model.error == nil)
        #expect(model.user?.allowPadCreation == false)
    }

    @Test(arguments: [true, false])
    func `available identity fields render in both languages`(allowed: Bool) throws {
        let result = try user(allowed ? "Ada" : nil, allowed: allowed)
        for locale in ["en", "es"] {
            let renderer = ImageRenderer(content: InterviewKeyOwnerDetails(user: result)
                .frame(width: 340).environment(\.locale, Locale(identifier: locale)))
            #expect((renderer.nsImage?.size.height ?? 0) > 0)
        }
    }
}
