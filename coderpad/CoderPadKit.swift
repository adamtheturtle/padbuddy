//
//  CoderPadKit.swift
//  coderpad
//

// The CoderPad REST API client - the typed models, request bodies, `CoderPadError`,
// and `CoderPadClient` - now lives in the public `CoderPadKit` package (#569), with the
// in-process fake API in its `CoderPadKitMock` companion. Both are re-exported here so
// the rest of the app keeps using them unqualified, with no per-file import, mirroring
// how `BuddyAppKit.swift` re-exports `BuddyAppKit`.
//
// The presentation overlay (`PadState.label`/`systemImage`, `InterviewType.label`) and
// the localized `CoderPadError` messages stay app-side in `CoderPadKit+Presentation.swift`,
// so the library remains locale-free while the app keeps its String Catalog translations.
@_exported import CoderPadKit
@_exported import CoderPadKitMock
