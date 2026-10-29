import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad event actor identities")
struct PadEventActorIdentityTests {
    private func event(_ name: String?, email: String?, at seconds: TimeInterval) -> PadEvent {
        PadEvent(message: "", kind: "typed", metadata: nil, userName: name,
                 userEmail: email, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func `a name gains its unique email without splitting the run`() throws {
        let groups = PadEventGrouping.group([
            event("Ada", email: nil, at: 1), event("Ada", email: "ada@example.com", at: 2)
        ])
        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.count == 2)
        #expect(group.actorIdentity == "email:ada@example.com")
    }

    @Test func `a later name improves the label without changing the starting timestamp`() throws {
        let group = try #require(PadEventGrouping.group([
            event(nil, email: "ada@example.com", at: 1), event("Ada", email: "ada@example.com", at: 2)
        ]).first)
        #expect(PadEventPresentationCache.actor(group.actorEvent) == "Ada")
        #expect(group.representative.createdAt == Date(timeIntervalSince1970: 1))
    }

    @Test func `active emphasis follows identity across name and email labels`() {
        let cache = PadEventPresentationCache()
        cache.refresh(events: [event("Ada", email: "ada@example.com", at: 1),
                               event(nil, email: "ada@example.com", at: 900)], revision: 1)
        #expect(cache.groups.count == 2)
        #expect(cache.groups.allSatisfy { $0.actorIdentity == cache.activeParticipant })
    }

    @Test func `ambiguous names do not join distinct people`() {
        let events = [event("Sam", email: "first@example.com", at: 1),
                      event("Sam", email: nil, at: 2),
                      event("Sam", email: "second@example.com", at: 3)]
        #expect(PadEventGrouping.group(events).count == 3)
        #expect(PadEventActorIdentity(events: events).key(for: events[1]) == nil)
    }

    @Test func `oversized identity fields cannot collide through truncation`() {
        let oversized = event("Ada", email: String(repeating: "a", count: 255), at: 1)
        #expect(PadEventActorIdentity(events: [oversized]).key(for: oversized) == nil)
    }
}
