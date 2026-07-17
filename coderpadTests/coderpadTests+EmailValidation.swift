//
//  coderpadTests+EmailValidation.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Email validation")
struct EmailValidationTests {
    @Test
    func `plausible email addresses are accepted`() {
        #expect(EmailValidation.isPlausibleAddress("ada@example.com"))
        #expect(EmailValidation.isPlausibleAddress("a.b+tag@sub.example.co"))
    }

    @Test
    func `malformed email addresses are rejected`() {
        let bad = ["", "\n", "@", "person@", "@example.com", "not-an-email", "a@b",
                   "a@.com", "a@example.com.", "two words@example.com", "a@@example.com"]
        for value in bad {
            #expect(!EmailValidation.isPlausibleAddress(value), "\(value) should be rejected")
        }
    }
}
