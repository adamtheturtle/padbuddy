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
        #expect(EmailValidation.isPlausibleAddress("o'brien_1%x@example-host.org"))
    }

    @Test
    func `malformed email addresses are rejected`() {
        let bad = ["", "\n", "@", "person@", "@example.com", "not-an-email", "a@b",
                   "a@.com", "a@example.com.", "two words@example.com", "a@@example.com"]
        for value in bad {
            #expect(!EmailValidation.isPlausibleAddress(value), "\(value) should be rejected")
        }
    }

    @Test
    func `consecutive dots in the domain are rejected`() {
        #expect(!EmailValidation.isPlausibleAddress("a@example..com"))
        #expect(!EmailValidation.isPlausibleAddress("a@..com"))
    }

    @Test
    func `illegal local part punctuation is rejected`() {
        let bad = ["a(b)@example.com", "a,b@example.com", "a:b@example.com",
                   "a[b]@example.com", "a\"b@example.com", ".a@example.com",
                   "a.@example.com", "a..b@example.com", "a\\b@example.com"]
        for value in bad {
            #expect(!EmailValidation.isPlausibleAddress(value), "\(value) should be rejected")
        }
    }

    @Test
    func `control and format characters are rejected`() {
        #expect(!EmailValidation.isPlausibleAddress("a\u{0000}b@example.com"))
        #expect(!EmailValidation.isPlausibleAddress("a\u{200D}b@example.com"))
        #expect(!EmailValidation.isPlausibleAddress("a@exam\u{0007}ple.com"))
    }

    @Test
    func `hyphen edges in domain labels are rejected`() {
        #expect(!EmailValidation.isPlausibleAddress("a@-example.com"))
        #expect(!EmailValidation.isPlausibleAddress("a@example-.com"))
        #expect(EmailValidation.isPlausibleAddress("a@ex-ample.com"))
    }

    @Test
    func `normalization trims and lowercases only the domain`() {
        #expect(EmailValidation.normalized("  Ada.B@EXAMPLE.Com\n") == "Ada.B@example.com")
        #expect(EmailValidation.normalized("no-at-sign") == "no-at-sign")
        #expect(EmailValidation.normalized("").isEmpty)
    }
}
