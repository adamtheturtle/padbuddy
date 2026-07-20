//
//  AutoRefreshPolicy.swift
//  coderpad
//

import Foundation

enum AutoRefreshPolicy {
    /// Adds up to ±10% jitter and exponentially backs off consecutive failures.
    /// The cap keeps a prolonged outage from disabling background recovery entirely.
    static func interval(base: Duration, consecutiveFailures: Int, jitter: Double = .random(in: -0.1 ... 0.1)) -> Duration {
        let failures = min(max(consecutiveFailures, 0), 5)
        let boundedJitter = min(max(jitter, -0.1), 0.1)
        return base * (1 << failures) * (1 + boundedJitter)
    }
}
