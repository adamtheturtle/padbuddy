//
//  coderpadTests+SearchInterpreter.swift
//  coderpadTests
//

@testable import coderpad
import Foundation
import Testing

// MARK: - SearchInterpreter value resolution

/// These cover the pure mapping from the model's free-form output onto the real
/// filter values — the part that must never apply a value the list can't honor.
/// The model call itself isn't exercised (it's on-device and gated to macOS 26+).

private let languages = ["python3", "javascript", "sql"]
private let owners = [
    SearchInterpreter.OwnerOption(email: "alice@acme.com", name: "Alice Adams"),
    SearchInterpreter.OwnerOption(email: "rdimarco@acme.com", name: "Rob Di Marco")
]

@Test func resolvesLanguageByExactCode() {
    #expect(SearchInterpreter.resolveLanguage("python3", in: languages) == "python3")
}

@Test func resolvesLanguageByDisplayNameCaseInsensitively() {
    #expect(SearchInterpreter.resolveLanguage("JavaScript", in: languages) == "javascript")
}

@Test func unknownLanguageResolvesToNil() {
    #expect(SearchInterpreter.resolveLanguage("brainfuck", in: languages) == nil)
    #expect(SearchInterpreter.resolveLanguage("", in: languages) == nil)
}

@Test func resolvesOwnerByNameEmailAndSubstringReturningEmail() {
    // A full display name (what the model usually echoes) resolves to the email.
    #expect(SearchInterpreter.resolveOwner("Rob Di Marco", in: owners) == "rdimarco@acme.com")
    // A first name still resolves via substring.
    #expect(SearchInterpreter.resolveOwner("rob", in: owners) == "rdimarco@acme.com")
    // An exact email resolves too.
    #expect(SearchInterpreter.resolveOwner("alice@acme.com", in: owners) == "alice@acme.com")
    #expect(SearchInterpreter.resolveOwner("carol", in: owners) == nil)
}

@Test func resolvesTeamByExactAndSubstringButNotVagueTerms() {
    let teams = ["Platform", "Mobile"]
    #expect(SearchInterpreter.resolveTeam("Platform", in: teams) == "Platform")
    #expect(SearchInterpreter.resolveTeam("mob", in: teams) == "Mobile")
    // A vague "my team" matches no real team, so no team filter is set (and it
    // must never fall through to the owner field).
    #expect(SearchInterpreter.resolveTeam("my team", in: teams) == nil)
    #expect(SearchInterpreter.resolveTeam("", in: teams) == nil)
}

@Test func resolvesStateSynonymsButRejectsUnknown() {
    #expect(SearchInterpreter.resolveState("started") == .active)
    #expect(SearchInterpreter.resolveState("finished") == .ended)
    #expect(SearchInterpreter.resolveState("pending") == .pending)
    // The catch-all `.other` must not leak through as a filter.
    #expect(SearchInterpreter.resolveState("archived") == nil)
    #expect(SearchInterpreter.resolveState("") == nil)
}

@Test func resolvesTypeToCanonicalRawValue() {
    #expect(SearchInterpreter.resolveType("take_home") == "take-home")
    #expect(SearchInterpreter.resolveType("live") == "live")
    #expect(SearchInterpreter.resolveType("whatever") == nil)
}

@Test func resolvesDateRangeOnlyForKnownWindows() {
    #expect(SearchInterpreter.resolveDateRange("Last 7 Days") == "last 7 days")
    #expect(SearchInterpreter.resolveDateRange("yesterday") == nil)
}

@Test func resolvesDraftStatus() {
    #expect(SearchInterpreter.resolveDraft("Draft") == "draft")
    #expect(SearchInterpreter.resolveDraft("published") == "published")
    #expect(SearchInterpreter.resolveDraft("retired") == nil)
}

@Test func optionListCapsLength() {
    let many = (1 ... 100).map { "lang\($0)" }
    let list = SearchInterpreter.optionList(many, limit: 3)
    #expect(list == "lang1, lang2, lang3")
}
