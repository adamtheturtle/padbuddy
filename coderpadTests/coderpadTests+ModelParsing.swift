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
