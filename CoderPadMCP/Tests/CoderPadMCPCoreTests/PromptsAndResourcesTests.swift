//
//  PromptsAndResourcesTests.swift
//  CoderPadMCPCoreTests
//
//  Tests for the MCP prompts and resources the server exposes (#517): the prompt
//  catalog and its rendering, and the resource catalog plus URI parsing.
//

@testable import CoderPadMCPCore
import Foundation
import MCP
import Testing

// MARK: - Prompts

@Suite("Prompts")
struct PromptsTests {
    @Test
    func `the catalog advertises the expected prompts`() {
        let names = interviewPrompts.map(\.name)
        #expect(names == ["review_pad_code", "summarize_pad", "compare_pads", "draft_question"])
        // Every prompt declares at least one required argument.
        for prompt in interviewPrompts {
            #expect(prompt.arguments?.contains { $0.required == true } == true)
        }
    }

    @Test
    func `review_pad_code renders a user message naming the pad and the tool`() throws {
        let result = try renderPrompt(name: "review_pad_code", arguments: ["pad_id": "abc123"])
        #expect(result.messages.count == 1)
        let message = try #require(result.messages.first)
        #expect(message.role == .user)
        guard case let .text(text) = message.content else {
            Issue.record("expected text content")
            return
        }

        #expect(text.contains("abc123"))
        #expect(text.contains("get_pad_code"))
        #expect(text.contains("get_pad_code tool with pad: \"abc123\""))
        #expect(text.contains("get_pad with pad: \"abc123\""))
        #expect(!text.contains("with id"))
    }

    @Test
    func `pad prompts name the pad tool argument`() throws {
        let promptArguments = ["pad_id": "abc123"]
        for name in ["review_pad_code", "summarize_pad"] {
            let result = try renderPrompt(name: name, arguments: promptArguments)
            guard case let .text(text) = try #require(result.messages.first).content else {
                Issue.record("expected text content")
                return
            }

            #expect(text.contains("pad: \"abc123\""))
            #expect(!text.contains("with id"))
        }

        let comparison = try renderPrompt(name: "compare_pads", arguments: ["pad_ids": "abc123, def456"])
        guard case let .text(text) = try #require(comparison.messages.first).content else {
            Issue.record("expected text content")
            return
        }

        #expect(text.contains("pad argument"))
    }

    @Test
    func `compare_pads splits and quotes each id`() throws {
        let result = try renderPrompt(name: "compare_pads", arguments: ["pad_ids": "a, b ,c"])
        guard case let .text(text) = try #require(result.messages.first).content else {
            Issue.record("expected text content")
            return
        }

        #expect(text.contains("\"a\""))
        #expect(text.contains("\"b\""))
        #expect(text.contains("\"c\""))
    }

    @Test
    func `draft_question folds in optional language and difficulty`() throws {
        let result = try renderPrompt(
            name: "draft_question",
            arguments: ["topic": "binary trees", "language": "python", "difficulty": "medium"]
        )
        guard case let .text(text) = try #require(result.messages.first).content else {
            Issue.record("expected text content")
            return
        }

        #expect(text.contains("binary trees"))
        #expect(text.contains("python"))
        #expect(text.contains("medium"))
    }

    @Test
    func `a missing required argument throws missingArgument`() {
        #expect(throws: PromptError.missingArgument("pad_id")) {
            try renderPrompt(name: "review_pad_code", arguments: nil)
        }
        // Whitespace-only counts as missing.
        #expect(throws: PromptError.missingArgument("pad_id")) {
            try renderPrompt(name: "summarize_pad", arguments: ["pad_id": "   "])
        }
        // An all-empty comma list is treated as missing.
        #expect(throws: PromptError.missingArgument("pad_ids")) {
            try renderPrompt(name: "compare_pads", arguments: ["pad_ids": " , , "])
        }
    }

    @Test
    func `an unknown prompt throws unknownPrompt`() {
        #expect(throws: PromptError.unknownPrompt("nope")) {
            try renderPrompt(name: "nope", arguments: nil)
        }
    }

    @Test
    func `prompts encode to valid JSON-RPC descriptors`() throws {
        let data = try JSONEncoder().encode(interviewPrompts[0])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["name"] as? String == "review_pad_code")
        #expect(object["arguments"] is [Any])
    }
}

// MARK: - Resources

@Suite("Resources")
struct ResourcesTests {
    @Test
    func `static resources cover quota and organization`() {
        let uris = staticResources.map(\.uri)
        #expect(uris.contains("coderpad://quota"))
        #expect(uris.contains("coderpad://organization"))
    }

    @Test
    func `templates cover pad, pad code, and question`() {
        let patterns = resourceTemplates.map(\.uriTemplate)
        #expect(patterns.contains("coderpad://pad/{id}"))
        #expect(patterns.contains("coderpad://pad/{id}/code"))
        #expect(patterns.contains("coderpad://question/{id}"))
    }

    @Test
    func `parseResourceURI maps each known shape`() {
        #expect(parseResourceURI("coderpad://quota") == .quota)
        #expect(parseResourceURI("coderpad://organization") == .organization)
        #expect(parseResourceURI("coderpad://pad/abc123") == .pad("abc123"))
        #expect(parseResourceURI("coderpad://pad/abc123/code") == .padCode("abc123"))
        #expect(parseResourceURI("coderpad://question/42") == .question(42))
    }

    @Test
    func `parseResourceURI decodes percent-encoded ids`() {
        #expect(parseResourceURI("coderpad://pad/a%20b") == .pad("a b"))
    }

    @Test
    func `parseResourceURI rejects unknown or malformed URIs`() {
        #expect(parseResourceURI("https://example.com/pad/1") == nil)
        #expect(parseResourceURI("coderpad://unknown") == nil)
        #expect(parseResourceURI("coderpad://question/not-a-number") == nil)
        #expect(parseResourceURI("coderpad://pad") == nil)
        #expect(parseResourceURI("not a uri") == nil)
    }

    @Test
    func `resources encode to valid JSON-RPC descriptors`() throws {
        let data = try JSONEncoder().encode(staticResources[0])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["uri"] as? String == "coderpad://quota")
        #expect(object["mimeType"] as? String == "application/json")
    }
}
