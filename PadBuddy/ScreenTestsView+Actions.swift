//
//  ScreenTestsView+Actions.swift
//  coderpad
//
//  The test-session row actions (write paths, #437): the context menu, the focused
//  command target, drag payload, open-in-window, and the resend / cancel / delete
//  mutations. Split from ScreenTestsView.swift to keep it within the lint length
//  budgets.
//

#if os(macOS)
    import AppKit
#endif
import FastList
import SwiftUI

extension ScreenTestsView {
    /// The right-click menu for a row, gated by status: resend and cancel apply only to
    /// an invitation the candidate hasn't started yet ("waiting"); delete is always
    /// available behind a confirmation. "Open in New Window" mirrors the double-click.
    func testTableMenuItems(_ test: ScreenTestSession) -> [MenuItem] {
        var items: [MenuItem] = [
            .button(title: String(localized: "Open in New Window")) { openTestWindow(test) },
            .button(title: String(localized: "Copy Test Session")) { Clipboard.copy(test.screenCopyText) },
            .separator
        ]
        if ScreenTestStatusPolicy.isWaiting(test.status) {
            items.append(.button(title: String(localized: "Resend Invitation"),
                                 isEnabled: !isReadOnly && isActionContextCurrent) {
                    Task { await resend(test) }
                })
            items.append(.button(title: String(localized: "Cancel Invitation"),
                                 isEnabled: !isReadOnly && isActionContextCurrent) {
                    Task { await cancel(test) }
                })
            items.append(.separator)
        }
        items.append(.button(title: String(localized: "Delete Test Session"),
                             isEnabled: !isReadOnly && isActionContextCurrent, role: .destructive) {
                guard isActionContextCurrent else { return }

                testPendingDelete = test
            })
        return items
    }

    var selectedTestAction: ScreenTestAction? {
        guard let selectedTest else { return nil }

        let selectedID = selectedTest.id

        return ScreenTestAction(id: selectedID, accountID: accountID, status: selectedTest.status,
                                contentFingerprint: selectedTest.screenCopyText.hashValue) {
            guard let current = tests.first(where: { $0.id == selectedID }) else { return }

            Clipboard.copy(current.screenCopyText)
        } openWindow: {
            guard let current = tests.first(where: { $0.id == selectedID }) else { return }

            openTestWindow(current)
        } resend: {
            guard isActionContextCurrent else { return }
            guard let current = tests.first(where: { $0.id == selectedID }) else { return }

            Task { await resend(current) }
        } cancel: {
            guard isActionContextCurrent else { return }
            guard let current = tests.first(where: { $0.id == selectedID }) else { return }

            Task { await cancel(current) }
        } delete: {
            guard isActionContextCurrent else { return }
            guard let current = tests.first(where: { $0.id == selectedID }) else { return }

            testPendingDelete = current
        }
    }

    #if os(macOS)
        func testPasteboardItem(_ test: ScreenTestSession) -> NSPasteboardItem? {
            let item = NSPasteboardItem()
            if let url = test.screenURL {
                item.setString(url.absoluteString, forType: .URL)
            }
            item.setString(test.screenCopyText, forType: .string)
            return item
        }
    #endif

    /// Opens a test session's report in its own window (#474). The owning account is
    /// the explicit `accountID` captured when this campaign detail was constructed.
    func openTestWindow(_ test: ScreenTestSession) {
        openWindow(id: "screen-test", value: ScreenTestWindowID(account: accountID, id: test.id))
    }

    func resend(_ test: ScreenTestSession) async {
        // The command can be invoked repeatedly (menu, focused commands) while a
        // mutation is in flight; each duplicate would email the candidate again
        // (#900), and a concurrent cancel could revoke the invitation being resent
        // (#1854). Offline, the write can only fail - don't start it (#1855).
        guard isActionContextCurrent, ScreenTestStatusPolicy.isWaiting(test.status), !isReadOnly,
              mutatingIDs.insert(test.id).inserted else { return }

        defer { mutatingIDs.remove(test.id) }
        do {
            try await client.resendTest(id: test.id)
            guard isActionContextCurrent else { return }

            showResentConfirmation = true
        } catch {
            guard isActionContextCurrent else { return }

            recordFailure(operation: String(localized: "Resend invitation"), test: test, error: error)
        }
    }

    func cancel(_ test: ScreenTestSession) async {
        // Same in-flight and read-only gate as resend: duplicate invocations raced
        // the row reload and sent concurrent cancellation requests (#1852, #1855).
        guard isActionContextCurrent, ScreenTestStatusPolicy.isWaiting(test.status), !isReadOnly,
              mutatingIDs.insert(test.id).inserted else { return }

        defer { mutatingIDs.remove(test.id) }
        do {
            try await client.cancelTest(id: test.id)
            guard isActionContextCurrent else { return }

            // The server mutation succeeded: refresh this row before the full reload,
            // so a failed reconciliation can't leave it "waiting" with Cancel/Resend
            // still offered for an already-canceled invitation (#810). If even the
            // single-session refetch fails, retain the valid server-backed row and
            // mark the one fact the successful mutation established locally. A later
            // successful reload replaces it with the complete server representation.
            let fresh = try? await client.getTest(id: test.id, withCommunityStats: false)
            if let index = tests.firstIndex(where: { $0.id == test.id }) {
                tests[index] = ScreenCancelReconciliation.session(current: tests[index], fresh: fresh)
            }
            refreshDerived()
            await load()
        } catch {
            guard isActionContextCurrent else { return }

            recordFailure(operation: String(localized: "Cancel invitation"), test: test, error: error)
        }
    }

    func delete(_ test: ScreenTestSession) async {
        // Duplicate destructive requests raced each other and reloaded the list
        // after another deletion already succeeded (#1853); offline the request can
        // only fail (#1855).
        guard isActionContextCurrent, !isReadOnly,
              mutatingIDs.insert(test.id).inserted else { return }

        defer { mutatingIDs.remove(test.id) }
        do {
            try await client.deleteTest(id: test.id)
            guard isActionContextCurrent else { return }

            // The server mutation succeeded: remove the row locally first, so a
            // failed reconciliation reload can't resurrect it (#810); the stale
            // banner reports the reload failure separately.
            selectedIDs.remove(test.id)
            tests.removeAll { $0.id == test.id }
            refreshDerived()
            await load()
        } catch {
            guard isActionContextCurrent else { return }

            recordFailure(operation: String(localized: "Delete test session"), test: test, error: error)
        }
    }

    func recordFailure(operation: String, test: ScreenTestSession, error: any Error) {
        let shouldPresent = actionErrors.isEmpty
        let accountName = accountID.map { id in
            AccountsStore.shared.accounts.first(where: { $0.id == id })?.name ?? id.uuidString
        } ?? client.baseURL.host()
        actionErrors.append(ScreenActionFailure(
            operation: operation,
            testID: test.id,
            candidate: test.screenCandidateDisplay,
            accountName: accountName,
            reason: (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        ))
        if shouldPresent {
            actionErrorPresented = true
        }
    }
}

nonisolated enum ScreenCancelReconciliation {
    static func session(current: ScreenTestSession, fresh: ScreenTestSession?) -> ScreenTestSession {
        guard let fresh else {
            var cancelled = current
            cancelled.status = "cancelled"
            return cancelled
        }

        return fresh
    }
}
