//
//  coderpadTests+AccountValidationThrottle.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Account validation retry pacing")
struct AccountValidationThrottleTests {
    @Test(arguments: [
        (1, Duration.seconds(2)),
        (2, Duration.seconds(4)),
        (3, Duration.seconds(8)),
        (4, Duration.seconds(16)),
        (5, Duration.seconds(30)),
        (20, Duration.seconds(30))
    ])
    func `failure cooldown grows exponentially and caps`(failures: Int, expected: Duration) {
        #expect(AccountEditor.validationCooldown(afterFailures: failures) == expected)
    }
}
