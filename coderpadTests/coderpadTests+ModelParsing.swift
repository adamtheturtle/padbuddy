//
//  coderpadTests+ModelParsing.swift
//  coderpadTests
//
//  Tests for OnDeviceModelParsing: reconstructing labeled sections and keyed
//  fields from the on-device model's plain-text replies.
//

@testable import CoderPad
import Foundation
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
