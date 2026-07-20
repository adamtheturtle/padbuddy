# Localization audit

Audited July 2026 for issue #689.

## Coverage

- The app, widget, App Shortcuts, Focus filter, menu commands, alerts, errors,
  empty states, and Info.plist metadata use the five checked-in String Catalogs.
- `scripts/check-localization.swift` recursively validates ordinary strings,
  App Shortcut string sets, and plural/device/width variations. CI requires a
  non-empty, non-new Spanish unit for every active translatable entry.
- English remains the source language; `en-GB` is intentionally a sparse regional
  override. Strings explicitly marked `shouldTranslate: false` are product names,
  protocol identifiers, or other invariant content.
- The catalogs currently pass the strict completeness check with no missing Spanish
  translations.

## Layout smoke tests

`DesignSystemRenderTests` rasterizes question-detail summary, test-case, starter-code,
and empty-materials layouts at compact and wide widths in light and dark appearances.
It additionally renders a compact Spanish summary and a compact right-to-left
materials pane. These tests catch crashes, zero-size layouts, and the most likely
compact-width regressions without committing OS-sensitive pixel snapshots.

App Store listing text and screenshots are maintained outside this repository and
must be checked in App Store Connect during each release submission.
