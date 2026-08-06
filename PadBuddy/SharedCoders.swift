//
//  SharedCoders.swift
//  coderpad
//
//  One `JSONEncoder`/`JSONDecoder` for the stores that serialize on every mutation.
//
//  Several stores allocated a fresh coder per call — and they call several times per
//  save (the local blob, its tombstones, and both again for the cloud mirror), on
//  paths that run whenever a favourite is toggled, a pad is opened, or a filter
//  changes (#2437, #2438, #2443, #2444, #2445). Both types are stateless once
//  configured, so a shared instance behaves identically.
//
//  These are the *default*-configured coders. A store needing a custom date or key
//  strategy keeps its own — see `CoderPadClient.decoder` and
//  `JSONLLog.iso8601Encoder`.
//

import Foundation

@MainActor
enum SharedCoders {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}
