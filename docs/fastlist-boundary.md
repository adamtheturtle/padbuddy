# FastList Dependency Boundary

This records the completed dependency audit for [#683](https://github.com/adamtheturtle/padbuddy/issues/683).

## Decision

- Keep macOS pad, merged-pad, and Screen test lists on `FastList`.
  Its AppKit backend provides the measured large-list performance, selection, scroll restoration, context menus, and drag hooks those surfaces require.
- Keep `MacQuestionTable` as the domain-specific macOS question renderer.
  It uses only FastList's small `SwipeAction` and `MenuItem` value types rather than generic hosted rows.
- Keep iOS pad and question lists on FastList's native SwiftUI backend.
  Replacing that backend with parallel app-owned `List` implementations would duplicate selection, swipe, context-menu, drag, and scroll behavior without reducing the shipped dependency.
- App-owned row layout, favorite drag payloads, menu construction, and action semantics stay in coderpad.
  `FastListRowMetrics` is intentionally app-owned.

## Import Inventory

Direct imports are limited to files that use package symbols:

- list renderers: `PadsView+Sidebar`, `MergedPadsView+List`, `QuestionsView+List`, `MergedQuestionsView+List`, and `ScreenTestsView`
- AppKit question table: `MacQuestionTable`
- menu/action adapters: the merged context-menu files, `ScreenTestsView+Actions`, and `FavoritesDrag`

`DesignSystem.swift` does not re-export FastList.
Row and layout files no longer import it merely because they are hosted by a FastList surface.
This makes package coupling visible and keeps a future reduced FastList API mechanical to adopt.
