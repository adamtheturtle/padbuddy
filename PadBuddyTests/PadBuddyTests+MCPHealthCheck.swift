//
//  PadBuddyTests+MCPHealthCheck.swift
//  PadBuddyTests
//

#if os(macOS)
    import Foundation
    @testable import PadBuddy
    import Testing

    @Suite("MCP health-check diagnostics (#4594)")
    struct MCPDiagnosticBufferTests {
        @Test func `collected output is readable`() {
            let buffer = MCPDiagnosticBuffer()

            #expect(buffer.append(Data("hello ".utf8), limit: 64))
            #expect(buffer.append(Data("world".utf8), limit: 64))

            #expect(buffer.text == "hello world")
        }

        @Test func `collection stops at the cap and reports that it is full`() {
            let buffer = MCPDiagnosticBuffer()

            let wantsMore = buffer.append(Data(repeating: UInt8(ascii: "x"), count: 100), limit: 8)

            #expect(!wantsMore)
            #expect(buffer.text.count == 8)
        }

        @Test func `a later append cannot exceed the cap`() {
            let buffer = MCPDiagnosticBuffer()
            _ = buffer.append(Data("1234".utf8), limit: 6)

            _ = buffer.append(Data("567890".utf8), limit: 6)

            #expect(buffer.text == "123456")
        }

        @Test func `completion is reported once the drain finishes`() {
            let buffer = MCPDiagnosticBuffer()
            #expect(!buffer.isComplete)

            buffer.markComplete()

            #expect(buffer.isComplete)
        }
    }

#endif
