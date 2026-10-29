//
//  ScreenTestDetailView+Warnings.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated struct ScreenWarningRow: Identifiable, Equatable {
    let id: Int
    let text: String
}

// MARK: - Fetching and report export

// (Formatting + the export document + previews live in
// ScreenTestDetailView+Formatting.swift, split for file length.)

extension ScreenTestDetailView {
    func refetch() async {
        let identity = fetchIdentity
        if detailFor != identity {
            // The view was reused for another session or account; drop the previous
            // copy so it can't render for the new identity (#1860).
            detail = nil
            detailFor = nil
            refreshError = nil
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        // Non-fatal: the list already gave us a usable session, so a failed refetch
        // leaves the existing data in place - but flagged stale rather than silently
        // presented as the current state (#921).
        do {
            let fresh = try await client.getTest(id: identity.testID, withCommunityStats: true)
            guard generation == fetchGeneration else { return }

            detail = fresh
            detailFor = identity
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            // Switching sessions cancels this task; that's not a refresh failure.
            // The generation guard keeps a superseded fetch's error out too (#1861).
            guard generation == fetchGeneration, !Task.isCancelled else { return }

            refreshError = RemoteLoadDiagnostic.display(
                (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    func scheduleReport(save: Bool) {
        guard let claim = reportRequest.claim() else { return }

        reportError = nil
        reportTask = Task {
            await openReport(save: save, claim: claim)
            guard reportRequest.isCurrent(claim) else { return }

            reportRequest.finish(claim)
            reportTask = nil
        }
    }

    /// Fetches the report PDF for the synchronously claimed per-view operation.
    private func openReport(save: Bool, claim: UUID) async {
        guard reportRequest.isCurrent(claim), !Task.isCancelled else { return }

        let identity = fetchIdentity
        do {
            let testID = identity.testID
            let anonymous = exportAnonymized ? true : nil
            let includeRank = exportIncludeRank ? true : nil
            let includeComparativeScore = exportIncludeComparative ? true : nil
            let data = try await ScreenReportOperationLimiter.shared.perform {
                try await client.testReport(
                    id: testID,
                    anonymous: anonymous,
                    includeRank: includeRank,
                    includeComparativeScore: includeComparativeScore
                )
            }
            // The detail view can be reused for another session/account while this
            // request was in flight; discard stale bytes instead of opening them under
            // the new candidate's identity (#4679).
            guard identity == fetchIdentity, reportRequest.isCurrent(claim), !Task.isCancelled else { return }

            // The bytes are handed to external viewers / written where the user
            // picked, so require an actual PDF of sane size: a malicious or broken
            // response must not exhaust memory or smuggle arbitrary content to a
            // viewer under a .pdf name (#1862).
            guard ScreenReportFiles.isWithinSizeLimit(data.count) else {
                reportError = String(localized: "The report is too large to open.")
                return
            }
            guard ScreenReportFiles.isLikelyPDF(data) else {
                reportError = String(localized: "The server did not return a PDF report.")
                return
            }

            if save {
                saveReport(data)
            } else {
                #if os(macOS)
                    // Staged in a unique, owner-only temp subdirectory (#804, #807): test
                    // IDs collide across accounts, and reports hold candidate data, so the
                    // file is single-use and swept again after opening / at next launch.
                    let url = try ScreenReportFiles.stage(data, testID: identity.testID)
                    let accepted = NSWorkspace.shared.open(url)
                    ScreenReportFiles.handleOpenResult(accepted, for: url)
                #else
                    // Quick Look previews the staged single-use file, which is swept
                    // again once the viewer has had time to load it (#808).
                    let url = try ScreenReportFiles.stage(data, testID: identity.testID)
                    reportPreviewURL = url
                    ScreenReportFiles.scheduleRemoval(of: url)
                #endif
            }
        } catch is CancellationError {
            return
        } catch {
            guard identity == fetchIdentity, reportRequest.isCurrent(claim), !Task.isCancelled else { return }

            reportError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Offers a save panel (sandbox-safe: the user grants write access to the chosen
    /// location) and writes the fetched PDF there.
    func saveReport(_ data: Data) {
        #if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "ScreenReport-\(test.id).pdf"
            // Re-check after the modal: the detail may have switched sessions while the
            // panel was open (#4679).
            guard panel.runModal() == .OK, let url = panel.url,
                  FetchIdentity(testID: test.id, apiKey: client.apiKey, baseURL: client.baseURL)
                  == fetchIdentity else { return }

            do {
                try data.write(to: url)
            } catch {
                reportError = error.localizedDescription
            }
        #else
            // The document exporter is sandbox-safe: it writes wherever the user
            // picks, mirroring the macOS save panel (#808).
            pendingReportExport = ScreenReportExportDocument(data: data)
        #endif
    }
}
