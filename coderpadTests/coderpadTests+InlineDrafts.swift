//
//  coderpadTests+InlineDrafts.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Inline edit draft stash")
@MainActor
struct InlineEditDraftsTests {
    /// The stash is a shared singleton, so each test works in its own key space
    /// and cleans up after itself rather than relying on ordering.
    private func key(_ suffix: String) -> String {
        "question/\(UUID().uuidString)/1/\(suffix)"
    }

    @Test
    func `a stashed draft is resumed at most once`() {
        let draftKey = key("description")
        InlineEditDrafts.shared.stash("in progress", for: draftKey)

        #expect(InlineEditDrafts.shared.take(for: draftKey) == "in progress")
        #expect(InlineEditDrafts.shared.take(for: draftKey) == nil)
    }

    @Test
    func `clearing drops a draft without resuming it`() {
        let draftKey = key("solution")
        InlineEditDrafts.shared.stash("in progress", for: draftKey)
        InlineEditDrafts.shared.clear(for: draftKey)

        #expect(InlineEditDrafts.shared.take(for: draftKey) == nil)
    }

    @Test
    func `window-qualified keys keep two windows' drafts apart`() {
        // InlineEditableText mixes its window's scope into the key it stashes
        // under. Two windows editing the same field must not share one slot:
        // before that, whichever editor unmounted last replaced the other
        // window's unsaved text and the other window resumed the wrong draft
        // (#2645).
        let field = key("description")
        let windowA = WindowScope()
        let windowB = WindowScope()
        #expect(windowA != windowB)

        InlineEditDrafts.shared.stash("window A text", for: "\(field)@\(windowA.token)")
        InlineEditDrafts.shared.stash("window B text", for: "\(field)@\(windowB.token)")

        #expect(InlineEditDrafts.shared.take(for: "\(field)@\(windowA.token)") == "window A text")
        #expect(InlineEditDrafts.shared.take(for: "\(field)@\(windowB.token)") == "window B text")
    }

    @Test
    func `removing an account drops its window-qualified drafts`() {
        // Account removal must still reach the drafts now that the key carries a
        // window suffix: it matches on the account UUID embedded mid-key (#1194).
        let account = UUID()
        let window = WindowScope()
        let draftKey = "question/\(account.uuidString)/7/description@\(window.token)"
        InlineEditDrafts.shared.stash("private prompt", for: draftKey)

        InlineEditDrafts.shared.removeAll(account: account)

        #expect(InlineEditDrafts.shared.take(for: draftKey) == nil)
    }

    @Test
    func `the unscoped window scope is stable across mounts`() {
        // Previews and render tests have no window, so their keys must not churn.
        let first = WindowScope.unscoped
        let second = WindowScope.unscoped
        #expect(first == second)
        // A real window's scope is always distinct from it, and from every other.
        let windowA = WindowScope()
        let windowB = WindowScope()
        #expect(windowA != first)
        #expect(windowA != windowB)
    }
}
