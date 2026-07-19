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
import Foundation

/// A client's backend identity, as a `.task(id:)` key.
///
/// This used to be an interpolated `String`, which meant every read built a fresh
/// string and serialized the `URL` to do it. SwiftUI re-evaluates a `.task(id:)` key
/// on every render pass, so that allocation happened constantly for a value only ever
/// compared for equality (#2259). Holding the two parts costs nothing to make and
/// compares just as well.
struct ClientTaskIdentity: Hashable {
    let apiKey: String
    let baseURL: URL
}

extension CoderPadClient {
    /// A stable identity for `.task(id:)` reload keys covering the full backend the
    /// client points at. Keying a section's load task on `apiKey` alone missed a
    /// changed Server URL: the same key against a different host kept the old task
    /// (and its stale data) alive (#709).
    var taskIdentity: ClientTaskIdentity {
        ClientTaskIdentity(apiKey: apiKey, baseURL: baseURL)
    }
}

extension ScreenClient {
    /// The Screen counterpart of `CoderPadClient.taskIdentity`: the same key can be
    /// re-homed between the US and EU regions, so the host is part of the identity.
    var taskIdentity: ClientTaskIdentity {
        ClientTaskIdentity(apiKey: apiKey, baseURL: baseURL)
    }
}
