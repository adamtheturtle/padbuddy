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

// MARK: - Grounding (reject model values the query doesn't support)

/// The on-device model over-fills fields the request never mentions (grabbing the
/// first option, echoing the whole query into the free-text search). These cover
/// the pure guards that keep a value only when the query actually supports it.

@Test func groundsLanguageOnlyWhenQueryNamesIt() {
    // Named by display name resolves and survives.
    #expect(SearchInterpreter.groundLanguage("javascript", query: "javascript pads") == "javascript")
    // The model's habit of grabbing the first option is rejected when unmentioned.
    #expect(SearchInterpreter.groundLanguage("python3", query: "pads by rob di marco") == nil)
    // A version-digit code is matched by its display name ("Python").
    #expect(SearchInterpreter.groundLanguage("python3", query: "draft python questions") == "python3")
    #expect(SearchInterpreter.groundLanguage(nil, query: "anything") == nil)
}

@Test func groundsOwnerByWholeNameTokenNotSubstring() {
    let owners = [
        SearchInterpreter.OwnerOption(email: "rdimarco@acme.com", name: "Rob Di Marco"),
        SearchInterpreter.OwnerOption(email: "mlin@acme.com", name: "Morgan Lin")
    ]
    #expect(SearchInterpreter.groundOwner("rdimarco@acme.com", query: "pads by rob di marco", owners: owners)
        == "rdimarco@acme.com")
    // "lin" must not match inside "linked", so the owner is dropped.
    #expect(SearchInterpreter.groundOwner("mlin@acme.com", query: "linked list pads", owners: owners) == nil)
    // The email's local part counts as a whole token.
    #expect(SearchInterpreter.groundOwner("rdimarco@acme.com", query: "rdimarco pads", owners: owners)
        == "rdimarco@acme.com")
    #expect(SearchInterpreter.groundOwner(nil, query: "anything", owners: owners) == nil)
}

@Test func groundsTeamOnlyWhenNamed() {
    #expect(SearchInterpreter.groundTeam("Platform", query: "pads for the platform team") == "Platform")
    #expect(SearchInterpreter.groundTeam("Platform", query: "javascript pads") == nil)
}

@Test func groundsStateTypeDraftAndDateOnlyWhenMentioned() {
    #expect(SearchInterpreter.groundState(.ended, query: "ended pads") == .ended)
    #expect(SearchInterpreter.groundState(.active, query: "recursion questions") == nil)
    #expect(SearchInterpreter.groundType("take-home", query: "take-home questions by alex") == "take-home")
    #expect(SearchInterpreter.groundType("live", query: "questions about recursion") == nil)
    #expect(SearchInterpreter.groundDraft("published", query: "published go questions") == "published")
    #expect(SearchInterpreter.groundDraft("draft", query: "go questions") == nil)
    #expect(SearchInterpreter.groundDateRange("last 7 days", query: "python pads from last week") == "last 7 days")
    #expect(SearchInterpreter.groundDateRange("today", query: "python pads") == nil)
}

@Test func groundsTextToGenuineKeywordsOnly() {
    let languages = ["python3", "javascript"]
    // A query the model echoes wholesale collapses to empty (the owner does the work).
    #expect(SearchInterpreter.groundText("pads by rob di marco", languages: languages,
                                         ownerName: "Rob Di Marco", team: "") == "")
    // A language word the request named is stripped (the language filter does the work).
    #expect(SearchInterpreter.groundText("javascript pads", languages: languages,
                                         ownerName: "", team: "") == "")
    // A real topic survives.
    #expect(SearchInterpreter.groundText("binary search pads", languages: languages,
                                         ownerName: "", team: "") == "binary search")
}
