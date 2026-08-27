//
//  PadBuddyTests+ModelParsing.swift
//  PadBuddyTests
//
//  Tests for OnDeviceModelParsing: reconstructing labeled sections and keyed
//  fields from the on-device model's plain-text replies.
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("On-device model parsing")
struct OnDeviceModelParsingTests {
    @Test
    func `labeled sections parse multiline values from line-prefixed labels`() {
        let reply = """
          TITLE: Two Sum
        DESCRIPTION: Find two numbers.
        Return their indices.
        SOLUTION:
        Use a dictionary.
        """

        let sections = OnDeviceModelParsing.labeledSections(reply, labels: ["TITLE", "DESCRIPTION", "SOLUTION"])

        #expect(sections["TITLE"] == "Two Sum")
        #expect(sections["DESCRIPTION"] == "Find two numbers.\nReturn their indices.")
        #expect(sections["SOLUTION"] == "Use a dictionary.")
    }

    @Test
    func `labeled sections allow whitespace before the colon`() {
        let reply = """
        TITLE : Two Sum
        DESCRIPTION\t: Find two numbers.
        TITLEISH : not a known header
        """

        let sections = OnDeviceModelParsing.labeledSections(reply, labels: ["TITLE", "DESCRIPTION"])

        #expect(sections["TITLE"] == "Two Sum")
        #expect(sections["DESCRIPTION"] == "Find two numbers.\nTITLEISH : not a known header")
    }

    @Test
    func `labeled sections ignore label-like text inside values`() {
        let reply = #"""
        SUMMARY: Prints a string containing OPTIMALITY: O(n).
        READABILITY:
        The line let title = "SUMMARY: demo" is just source code.
        OPTIMALITY: Linear time.
        """#

        let sections = OnDeviceModelParsing.labeledSections(
            reply,
            labels: ["SUMMARY", "READABILITY", "OPTIMALITY"]
        )

        #expect(sections["SUMMARY"] == "Prints a string containing OPTIMALITY: O(n).")
        #expect(sections["READABILITY"] == #"The line let title = "SUMMARY: demo" is just source code."#)
        #expect(sections["OPTIMALITY"] == "Linear time.")
    }

    /// A fenced code block quoting a label must not start that section, even
    /// when the real header hasn't appeared yet (#1962).
    @Test
    func `labeled sections ignore labels quoted inside code fences`() {
        let reply = """
        SUMMARY: Prints a banner.
        ```
        READABILITY: this is quoted source, not a header
        ```
        READABILITY: Clear and short.
        """

        let sections = OnDeviceModelParsing.labeledSections(reply, labels: ["SUMMARY", "READABILITY"])

        #expect(sections["SUMMARY"] == "Prints a banner.\n```\nREADABILITY: this is quoted source, not a header\n```")
        #expect(sections["READABILITY"] == "Clear and short.")
    }

    /// The model re-emitting the current section's header is a correction: the
    /// later occurrence wins over the stale first answer (#1963).
    @Test
    func `labeled sections keep the corrected repeat of the current section`() {
        let reply = """
        TITLE: Draft title
        TITLE: Corrected title
        DESCRIPTION: Body.
        """

        let sections = OnDeviceModelParsing.labeledSections(reply, labels: ["TITLE", "DESCRIPTION"])

        #expect(sections["TITLE"] == "Corrected title")
        #expect(sections["DESCRIPTION"] == "Body.")
    }

    @Test
    func `labeled sections ignore duplicate labels after their first header`() {
        let reply = """
        TITLE: Original
        DESCRIPTION:
        TITLE: This is part of the description, not a second title.
        SOLUTION: Done
        """

        let sections = OnDeviceModelParsing.labeledSections(reply, labels: ["TITLE", "DESCRIPTION", "SOLUTION"])

        #expect(sections["TITLE"] == "Original")
        #expect(sections["DESCRIPTION"] == "TITLE: This is part of the description, not a second title.")
        #expect(sections["SOLUTION"] == "Done")
    }

    @Test
    func `keyed fields normalize keys and drop empty or not-set values`() {
        let fields = OnDeviceModelParsing.keyedFields("""
        Date Range: last week
        owner_email: "polly@fawltytowers.co.uk"
        language: none
        state:
        """)

        #expect(fields["daterange"] == "last week")
        #expect(fields["owneremail"] == "polly@fawltytowers.co.uk")
        #expect(fields["language"] == nil)
        #expect(fields["state"] == nil)
    }

    @Test
    func `keyed fields strip only balanced matching quotes`() {
        let fields = OnDeviceModelParsing.keyedFields("""
        balanced: "value"
        apostrophe: 'value'
        leading: "value
        trailing: value'
        mismatched: "value'
        single: '
        """)

        #expect(fields["balanced"] == "value")
        #expect(fields["apostrophe"] == "value")
        #expect(fields["leading"] == "\"value")
        #expect(fields["trailing"] == "value'")
        #expect(fields["mismatched"] == "\"value'")
        #expect(fields["single"] == "'")
    }

    /// A key the model repeats with conflicting values is dropped entirely
    /// rather than trusting whichever occurrence came last (#1715, #1964);
    /// repeating the same value is harmless and kept.
    @Test
    func `keyed fields drop keys the model contradicts itself on`() {
        let fields = OnDeviceModelParsing.keyedFields("""
        language: python
        language: java
        state: open
        state: open
        """)

        #expect(fields["language"] == nil)
        #expect(fields["state"] == "open")
    }
}

@Suite("Model field bounds and normalization (#2425, #2427)")
struct ModelKeyedFieldBoundsTests {
    @Test
    func `a nonbreaking space normalizes like a plain one`() {
        // "date range" written with U+00A0 used to produce a different key from the
        // plain-space spelling, so downstream matching missed it (#2427).
        let plain = OnDeviceModelParsing.keyedFields("date range: last week")
        let nonbreaking = OnDeviceModelParsing.keyedFields("date\u{00A0}range: last week")
        #expect(plain == nonbreaking)
        #expect(plain["daterange"] == "last week")
        // Hyphens and underscores already folded; confirm they still agree.
        #expect(OnDeviceModelParsing.keyedFields("date_range: last week") == plain)
        #expect(OnDeviceModelParsing.keyedFields("date-range: last week") == plain)
    }

    @Test
    func `an over-long key or value is dropped`() {
        let longKey = String(repeating: "k", count: OnDeviceModelParsing.maxKeyLength + 1)
        #expect(OnDeviceModelParsing.keyedFields("\(longKey): value").isEmpty)

        let longValue = String(repeating: "v", count: OnDeviceModelParsing.maxValueLength + 1)
        #expect(OnDeviceModelParsing.keyedFields("key: \(longValue)").isEmpty)
    }

    @Test
    func `the field count is capped`() {
        let reply = (1 ... (OnDeviceModelParsing.maxFieldCount + 20))
            .map { "key\($0): value\($0)" }
            .joined(separator: "\n")
        #expect(OnDeviceModelParsing.keyedFields(reply).count == OnDeviceModelParsing.maxFieldCount)
    }

    @Test
    func `a well-formed reply is unaffected by the caps`() {
        let fields = OnDeviceModelParsing.keyedFields("owner: a@x.com\nlanguage: python3")
        #expect(fields["owner"] == "a@x.com")
        #expect(fields["language"] == "python3")
    }
}

@Suite("Model reply parsing work limits (#4566, #4567)")
struct ModelReplyParsingLimitsTests {
    private var parser: OnDeviceModelParsing.Type {
        OnDeviceModelParsing.self
    }

    @Test func `conflicting keys do not consume the accepted field cap`() {
        // Every key is offered twice with different values, so all of them conflict and
        // none should be kept — and none should crowd out the valid field that follows.
        var reply = ""
        for index in 0 ..< OnDeviceModelParsing.maxFieldCount {
            reply += "key\(index): a\n"
            reply += "key\(index): b\n"
        }
        reply += "language: python\n"

        let fields = OnDeviceModelParsing.keyedFields(reply)

        #expect(fields["language"] == "python")
        #expect(fields.count == 1)
    }

    @Test func `a conflicted key is not resurrected by a later repeat`() {
        let fields = OnDeviceModelParsing.keyedFields("k: a\nk: b\nk: a\n")

        #expect(fields["k"] == nil)
    }

    @Test func `a repeated identical value is still kept`() {
        let fields = OnDeviceModelParsing.keyedFields("k: a\nk: a\n")

        #expect(fields["k"] == "a")
    }

    @Test func `rejected lines are bounded rather than scanned forever`() {
        // Colonless lines never inserted anything, so the field cap never advanced and
        // every line was processed. The line limit bounds that work instead.
        let noise = String(repeating: "no colon here\n", count: OnDeviceModelParsing.maxLineCount * 4)

        let fields = OnDeviceModelParsing.keyedFields(noise + "language: python\n")

        // The valid field sits past the line limit, so it is not reached — the point is
        // that the parser stops rather than reading the whole reply.
        #expect(fields.isEmpty)
    }

    @Test func `a valid field within the line limit is still read`() {
        let noise = String(repeating: "no colon here\n", count: 10)

        let fields = OnDeviceModelParsing.keyedFields(noise + "language: python\n")

        #expect(fields["language"] == "python")
    }

    @Test func `the accepted field cap still applies`() {
        var reply = ""
        for index in 0 ..< (OnDeviceModelParsing.maxFieldCount + 20) {
            reply += "key\(index): value\n"
        }

        #expect(OnDeviceModelParsing.keyedFields(reply).count == OnDeviceModelParsing.maxFieldCount)
    }
}
