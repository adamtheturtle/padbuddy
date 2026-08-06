//
//  BuddyAppKit.swift
//  coderpad
//

// The zero-coupling app utilities — `Clipboard`, `URLOpener` (incl. `URL.staticURL`),
// `NetworkMonitor`, `RelativeDateLabel`, `MultiSelectLogic`, `SerialWriteQueue`, and
// `LenientElement` — now live in the local `BuddyAppKit` package (#511) so they can be
// shared with the HackerRank sibling app. Re-exported here so the rest of the app keeps
// using them unqualified, with no per-file import, mirroring how `DesignSystem.swift`
// re-exports `CoderPadDesignSystem`.
@_exported import BuddyAppKit

#if !APP_STORE && canImport(BuddySparkleUpdater)
    @_exported import BuddySparkleUpdater
#endif
