//
//  BuddyAppKit.swift
//  coderpad
//

// The zero-coupling app utilities — `Clipboard`, `URLOpener` (incl. `URL.staticURL`),
// `NetworkMonitor`, `RelativeDateLabel`, `MultiSelectLogic`, `SerialWriteQueue`, and
// `LenientElement` — live in the `buddy-kit` package (#511) so they can be shared with
// the HackerRank sibling app. It is resolved as a remote Swift package; a change to
// them belongs in that repository, followed by a pin bump here. Re-exported so the rest
// of the app keeps using them unqualified, with no per-file import, mirroring how
// `DesignSystem.swift` re-exports `BuddyDesignSystem`.
@_exported import BuddyAppKit

#if !APP_STORE && canImport(BuddySparkleUpdater)
    @_exported import BuddySparkleUpdater
#endif
