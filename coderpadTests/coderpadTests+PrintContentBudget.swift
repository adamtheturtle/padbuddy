//
//  coderpadTests+PrintContentBudget.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Print content budget (#1550)")
struct PrintContentBudgetTests {
    @Test
    func `the budget is aggregate across document sections`() {
        var budget = PrintContentBudget(maximumCharacters: 5)

        let first = budget.consume("abc")
        let second = budget.consume("def")
        let third = budget.consume("ghi")

        #expect(first.text == "abc")
        #expect(!first.truncated)
        #expect(second.text == "de")
        #expect(second.truncated)
        #expect(third.text.isEmpty)
        #expect(third.truncated)
    }

    @Test
    func `truncation preserves composed Unicode characters`() {
        let family = "👨‍👩‍👧‍👦"
        var budget = PrintContentBudget(maximumCharacters: 1)

        let result = budget.consume(family + "x")

        #expect(result.text == family)
        #expect(result.text.count == 1)
        #expect(result.truncated)
    }

    @Test
    func `remote labels are bounded on grapheme boundaries`() {
        let family = "👨‍👩‍👧‍👦"

        let result = PrintContentBudget.boundedLabel(String(repeating: family, count: 4), maximumCharacters: 2)

        #expect(result == family + family)
        #expect(result.count == 2)
    }
}
