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
        if test.status == "waiting" {
            items.append(.button(title: String(localized: "Resend Invitation"),
                                 isEnabled: !isReadOnly) { Task { await resend(test) } })
            items.append(.button(title: String(localized: "Cancel Invitation"),
                                 isEnabled: !isReadOnly) { Task { await cancel(test) } })
            items.append(.separator)
        }
        items.append(.button(title: String(localized: "Delete Test Session"),
                             isEnabled: !isReadOnly, role: .destructive) {
            testPendingDelete = test
        })
        return items
    }

    var selectedTestAction: ScreenTestAction? {
        guard let selectedTest else { return nil }

        return ScreenTestAction(id: selectedTest.id, status: selectedTest.status,
                                contentFingerprint: selectedTest.screenCopyText.hashValue) {
            Clipboard.copy(selectedTest.screenCopyText)
        } openWindow: {
            openTestWindow(selectedTest)
        } resend: {
            Task { await resend(selectedTest) }
        } cancel: {
            Task { await cancel(selectedTest) }
        } delete: {
            testPendingDelete = selectedTest
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
    /// the explicit `accountID` in the combined view (#442), else the current account.
    func openTestWindow(_ test: ScreenTestSession) {
        let owner = accountID ?? accounts.currentAccountID
        openWindow(id: "screen-test", value: ScreenTestWindowID(account: owner, id: test.id))
    }

    func resend(_ test: ScreenTestSession) async {
        // The command can be invoked repeatedly (menu, focused commands) while a
        // mutation is in flight; each duplicate would email the candidate again
        // (#900), and a concurrent cancel could revoke the invitation being resent
        // (#1854). Offline, the write can only fail - don't start it (#1855).
        guard !isReadOnly, mutatingIDs.insert(test.id).inserted else { return }

        defer { mutatingIDs.remove(test.id) }
        do {
            try await client.resendTest(id: test.id)
            showResentConfirmation = true
        } catch {
            actionError = message(for: error)
        }
    }

    func cancel(_ test: ScreenTestSession) async {
        // Same in-flight and read-only gate as resend: duplicate invocations raced
        // the row reload and sent concurrent cancellation requests (#1852, #1855).
        guard !isReadOnly, mutatingIDs.insert(test.id).inserted else { return }

        defer { mutatingIDs.remove(test.id) }
        do {
            try await client.cancelTest(id: test.id)
            // The server mutation succeeded: refresh this row before the full reload,
            // so a failed reconciliation can't leave it "waiting" with Cancel/Resend
            // still offered for an already-canceled invitation (#810). If even the
            // single-session refetch fails, drop the row; the next successful reload
            // restores it with its true status.
            if let fresh = try? await client.getTest(id: test.id, withCommunityStats: false),
               let index = tests.firstIndex(where: { $0.id == test.id }) {
                tests[index] = fresh
            } else {
                tests.removeAll { $0.id == test.id }
            }
            refreshDerived()
            await load()
        } catch {
            actionError = message(for: error)
        }
    }

    func delete(_ test: ScreenTestSession) async {
        // Duplicate destructive requests raced each other and reloaded the list
        // after another deletion already succeeded (#1853); offline the request can
        // only fail (#1855).
        guard !isReadOnly, mutatingIDs.insert(test.id).inserted else { return }

        defer { mutatingIDs.remove(test.id) }
        do {
            try await client.deleteTest(id: test.id)
            // The server mutation succeeded: remove the row locally first, so a
            // failed reconciliation reload can't resurrect it (#810); the stale
            // banner reports the reload failure separately.
            selectedIDs.remove(test.id)
            tests.removeAll { $0.id == test.id }
            refreshDerived()
            await load()
        } catch {
            actionError = message(for: error)
        }
    }

    func message(for error: any Error) -> String {
        (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
    }
}
