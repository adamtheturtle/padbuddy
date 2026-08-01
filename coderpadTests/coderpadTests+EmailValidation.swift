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

@Suite("Email validation edge cases")
struct EmailValidationEdgeCaseTests {
    @Test
    func `an ordinary address is plausible`() {
        #expect(EmailValidation.isPlausibleAddress("me@example.com"))
        #expect(EmailValidation.isPlausibleAddress("first.last+tag@sub.example.co.uk"))
    }

    @Test
    func `a second at sign is rejected`() {
        #expect(!EmailValidation.isPlausibleAddress("a@b@example.com"))
    }

    @Test
    func `a missing at sign is rejected`() {
        #expect(!EmailValidation.isPlausibleAddress("example.com"))
        #expect(!EmailValidation.isPlausibleAddress(""))
    }

    @Test
    func `whitespace anywhere is rejected`() {
        #expect(!EmailValidation.isPlausibleAddress(" me@example.com"))
        #expect(!EmailValidation.isPlausibleAddress("me@example.com "))
        #expect(!EmailValidation.isPlausibleAddress("me @example.com"))
        #expect(!EmailValidation.isPlausibleAddress("me@exa\tmple.com"))
    }

    @Test
    func `ascii control characters are rejected`() {
        #expect(!EmailValidation.isPlausibleAddress("me\u{0001}@example.com"))
        #expect(!EmailValidation.isPlausibleAddress("me@example.com\u{007F}"))
    }

    @Test
    func `non-ascii format characters are still rejected`() {
        // These are the ones that need the general-category lookup the fast path
        // skips for ASCII: a zero-width joiner and a right-to-left mark.
        #expect(!EmailValidation.isPlausibleAddress("me\u{200D}@example.com"))
        #expect(!EmailValidation.isPlausibleAddress("me@exa\u{200F}mple.com"))
    }
}
