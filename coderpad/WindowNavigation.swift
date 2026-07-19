//
//  WindowNavigation.swift
//  coderpad
//
//  The per-window half of the navigation state. `AppNavigation.shared` remains the
//  process-wide mailbox for navigation *requests* (menu commands, deep links, App
//  Intents queue durable one-shots there), but state that a window *publishes about
//  itself* - its list's result count, its Screen drill-down, its merged lists'
//  preset flags - must live per scene: with several main windows open (iPad
//  multi-window, and macOS detail windows) a single process-wide value made every
//  window display or act on whichever window published last (#887, #888, #908, #909).
//
//  Each `ContentView` owns one instance and injects it into its scene's environment
//  alongside that scene's `MergedRouting`.
//

import Foundation

@Observable
final class WindowNavigation {
    /// This window's visible section. Per scene, so navigating in one main window
    /// no longer retargets every other one (#907). Process-wide section *requests*
    /// (menu commands, deep links, intents, the sidebar's showX helpers) stay on
    /// `AppNavigation.shared` as `sectionRequest`, which the focused window
    /// consumes and applies here.
    var section: AppSection = .pads
    /// The visible list section's result-count summary (e.g. "12 pads"), published by
    /// the active list pane via ``publishSectionCount(_:)`` and shown by `MainSplit` as
    /// the window's toolbar subtitle beneath the section title. Routed through the
    /// guarded ``publishSectionCount(_:)`` (an `onChange` side effect, which fires once
    /// per settled value) rather than a SwiftUI preference, which SwiftUICore faulted
    /// on ("tried to update multiple times per frame"): a list's count can change
    /// across the several `body` passes that settle one frame.
    private(set) var sectionCountSubtitle = ""

    /// The section ``sectionCountSubtitle`` was published for, so `MainSplit` can ignore a
    /// count left over from the section just navigated away from - otherwise that stale
    /// count would linger under the new title until the new pane republishes its own,
    /// which lands a frame later and reads as a flash (the old title's count, then the
    /// new one). Set alongside the subtitle by ``publishSectionCount(_:)``.
    private(set) var sectionCountSection: AppSection?

    /// The campaign selected in this window's Screen section middle column. Selecting
    /// one drives the detail column's test-sessions list (#448). Kept here rather than
    /// as a `MainSplit` binding so it needs no threading through the shared split
    /// columns; the campaigns list owns it and the detail column observes it. Per
    /// scene, so another window's selection can't retarget this window's detail (#888).
    var screenCampaignSelection: ScreenCampaign?
    /// The account that owns ``screenCampaignSelection``. Screen campaign IDs are
    /// only unique inside one organization, so restoration must validate both (#1464).
    private(set) var screenCampaignAccountID: UUID?

    func publishScreenCampaign(_ campaign: ScreenCampaign?, accountID: UUID?) {
        screenCampaignSelection = campaign
        screenCampaignAccountID = campaign == nil ? nil : accountID
    }

    func screenCampaign(for accountID: UUID?) -> ScreenCampaign? {
        screenCampaignAccountID == accountID ? screenCampaignSelection : nil
    }

    /// The selected campaign's candidate-count subtitle (e.g. "12 candidates"), published
    /// by the tests list (which lives in the detail column, #448). The campaigns column
    /// reports it as the window subtitle while a campaign is selected, since the detail
    /// column's own count preference doesn't propagate out to the toolbar (#475). Per
    /// scene, so windows can't overwrite or blank one another's counts (#887).
    var screenTestsSubtitle = ""

    /// Which tests-list view instance last published ``screenTestsSubtitle``, so the
    /// deferred clear from a disappearing campaign view can't blank the subtitle a
    /// newly selected campaign just wrote (#805). Only the current owner may clear.
    var screenTestsSubtitleOwner: UUID?

    /// The live "Mine" preset state of each combined ("All Accounts") list in this
    /// window, republished by `MergedPadsView`/`MergedQuestionsView`. The sidebar
    /// reads it to aim its "My Pads"/"My Questions" toggles at what this window
    /// actually shows; the toggle requests themselves stay process-wide on
    /// `AppNavigation` (see `mergedPadsMineRequest`) until #910 scopes request
    /// delivery per scene.
    var mergedPadsMineOnly = false
    var mergedQuestionsMineOnly = false

    /// The live "Active" preset of this window's combined pads list - its `stateFilter`
    /// set to the in-progress session state - mirrored by the sidebar's "Active Pads"
    /// row. Follows ``mergedPadsMineOnly``.
    var mergedPadsActiveOnly = false

    /// Publish the active list section's result-count subtitle, tagged with the current
    /// section so `MainSplit` can tell it apart from a stale count. Called as an
    /// `onChange` side effect (see `reportsSectionCount`), which already fires once per
    /// settled value, so the set is synchronous: deferring it to the next runloop is
    /// what left the toolbar blank for a frame when switching sections (the new pane's
    /// count arrived after the section change had already cleared the old one).
    func publishSectionCount(_ subtitle: String) {
        let section = section
        guard sectionCountSubtitle != subtitle || sectionCountSection != section else { return }

        sectionCountSubtitle = subtitle
        sectionCountSection = section
    }
}
