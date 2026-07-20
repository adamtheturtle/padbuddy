//
//  Accounts+Account.swift
//  coderpad
//
//  The Account model and its owner-email canonicalization.
//

import Foundation
import SwiftUI

extension String {
    /// This email address reduced to the conservative mailbox form used for ownership
    /// checks: trimmed and lowercased only. The `+` character is legal in email local
    /// parts and is not a guaranteed alias convention for every organization, so matching
    /// `hello@acme.co` to `hello+team@acme.co` would risk treating another mailbox's pads
    /// as the configured user's.
    var canonicalOwnerEmail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// The CoderPad **Screen** region an account's Screen credentials belong to. Screen
/// is hosted per region (US / EU) on distinct hosts, so the API key alone isn't
/// enough — `Account.makeScreenClient()` points the client at the matching server.
/// Defaults to `.unitedStates`.
enum ScreenRegion: String, Codable, CaseIterable, Hashable {
    case unitedStates = "us"
    case europe = "eu"

    /// The Screen server base URL for this region.
    var baseURL: URL {
        switch self {
        case .unitedStates: ScreenClient.defaultBaseURL
        case .europe: ScreenClient.euBaseURL
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool
    /// The email of the org member this key belongs to, used to show "my" pads.
    /// The CoderPad API doesn't expose the key's owner, so the user picks it when
    /// validating the key — and saving is gated on it (see `canSave`). Normally a
    /// persisted account has one, matching the org-users API where email is
    /// non-optional; it can be empty for an in-progress draft or for an account
    /// migrated from the legacy single-key storage, which carries no email. Such an
    /// account still loads: dropping it would lose the API key with no recovery
    /// path, since migration already deleted the legacy credential (#767). The
    /// editor requires re-validation (which picks the email) before it can be saved
    /// again, and `owns(_:)` never matches on an empty email.
    var userEmail: String
    /// An optional override for the CoderPad server URL, for self-hosted or regional
    /// deployments. `nil`/empty means the standard hosted endpoint. Optional so
    /// accounts saved before this existed still decode.
    var baseURL: String?
    /// An optional SF Symbol name shown in place of the name's initials on the
    /// account's avatar, so multi-account users can tell similar accounts apart at a
    /// glance. `nil` means fall back to initials. Chosen from `iconSymbolChoices`.
    var iconSymbol: String?
    /// An optional avatar tint as an "#RRGGBB" hex string. `nil` means use the
    /// default (the app accent, or purple for demo accounts). A string rather than
    /// a `Color` so it encodes cleanly into the Keychain JSON.
    var tintHex: String?
    /// An optional CoderPad **Screen** API key. Screen is a separate product from the
    /// Interview API that `apiKey` talks to; storing it here lets one org identity span
    /// both. `nil`/empty means this account has no Screen access (the common case), so
    /// `makeScreenClient()` returns `nil`. Optional so accounts saved before Screen
    /// support still decode.
    var screenApiKey: String?
    /// Which Screen region (`us`/`eu`) `screenApiKey` belongs to: Screen is hosted on
    /// distinct per-region servers, so the key needs its region to reach the right one.
    /// Defaults to `.unitedStates`; ignored when no Screen key is set.
    var screenRegion: ScreenRegion

    init(name: String, apiKey: String, id: UUID = UUID(), isMock: Bool = false,
         userEmail: String = "", baseURL: String? = nil,
         iconSymbol: String? = nil, tintHex: String? = nil,
         screenApiKey: String? = nil, screenRegion: ScreenRegion = .unitedStates) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
        self.userEmail = userEmail
        self.baseURL = baseURL
        self.iconSymbol = iconSymbol
        self.tintHex = tintHex
        self.screenApiKey = screenApiKey
        self.screenRegion = screenRegion
    }

    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, isMock, userEmail, baseURL, iconSymbol, tintHex
        case screenApiKey, screenRegion
    }

    /// Custom decoding that tolerates a missing or empty user email rather than
    /// dropping the account: the legacy single-key migration persists an account
    /// with no email after deleting the original credential, so rejecting it here
    /// would silently lose the API key on the next launch with no recovery path
    /// (#767). The account editor requires re-validation (which picks the owner
    /// email) before such an account can be saved again. Encoding stays synthesized.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        isMock = try container.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        tintHex = try container.decodeIfPresent(String.self, forKey: .tintHex)
        screenApiKey = try container.decodeIfPresent(String.self, forKey: .screenApiKey)
        screenRegion = try container.decodeIfPresent(ScreenRegion.self, forKey: .screenRegion) ?? .unitedStates
    }

    /// The curated SF Symbols offered for an account's avatar. Deliberately small
    /// and generic so the picker stays a quick visual choice rather than a search
    /// through the full symbol library.
    static let iconSymbolChoices = [
        "building.2.fill", "briefcase.fill", "person.2.fill", "house.fill",
        "star.fill", "flag.fill", "hammer.fill", "globe.americas.fill"
    ]

    /// Parsed tints, keyed by their hex string.
    ///
    /// `AvatarCircle(account:)` reads `avatarTint` directly inside view bodies, so the
    /// hex parse re-ran on every render of every avatar (#2464). The parse is pure and
    /// the palette is a small fixed set, so memoizing by hex costs a dictionary lookup
    /// and bounds itself in practice. `Color?` is stored, so an unparseable hex is
    /// remembered as unparseable rather than being re-attempted each time.
    @MainActor private static var parsedTints: [String: Color?] = [:]

    /// The user-chosen avatar tint parsed from `tintHex`, or `nil` when unset or
    /// unparseable — leaving the default tint to apply.
    @MainActor
    var tintColor: Color? {
        guard let tintHex else { return nil }

        if let cached = Self.parsedTints[tintHex] { return cached }

        let parsed = Color(hex: tintHex)
        Self.parsedTints[tintHex] = parsed
        return parsed
    }

    /// The fallback tint when no custom color is chosen: purple for demo accounts,
    /// the app accent for real ones.
    var defaultTint: Color {
        isMock ? .purple : .accentColor
    }

    /// The tint to draw this account's avatar with: the custom color when set,
    /// otherwise `defaultTint`.
    @MainActor
    var avatarTint: Color {
        tintColor ?? defaultTint
    }

    /// The curated tint palette offered for an account's avatar, as "#RRGGBB" hex.
    /// A small fixed set (plus the "default" option in the picker) keeps choosing a
    /// color a quick visual pick rather than a full color well.
    static let tintChoices = [
        "#3478F6", "#9B59B6", "#FF2D55", "#FF3B30",
        "#FF9500", "#34C759", "#30B0C7", "#8E8E93"
    ]

    /// The account's Server URL override, parsed fallibly: the trimmed non-empty
    /// override as a usable HTTP(S) URL with a host, or nil when the field is blank
    /// or the text doesn't parse to one. Embedded credentials, a query, or a
    /// fragment are rejected outright: the resolved URL feeds authenticated API
    /// calls and synced account metadata, and `https://user:pass@host?token=…#…`
    /// must not ride along into either (#1155).
    nonisolated var baseURLOverride: URL? {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil
        else { return nil }

        return url
    }

    /// Whether the account has a non-empty Server URL override that isn't a usable
    /// HTTP(S) URL. Such an account must never fall back to the hosted endpoint:
    /// a request there would send a self-hosted or regional API key to the wrong
    /// host (#849). Only a genuinely blank field selects the hosted default.
    nonisolated var hasMalformedBaseURLOverride: Bool {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty && baseURLOverride == nil
    }

    /// Synced credentials may replace a working local snapshot only when they can
    /// actually construct the same supported clients. Legacy blank owner email is
    /// intentionally allowed; the editor repairs it on the next validation (#2852).
    nonisolated var isUsableSyncedCredential: Bool {
        if isMock { return true }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasMalformedBaseURLOverride
    }

    /// Whether background views may contact the real Interview API for this
    /// account. Demo accounts have usable in-process clients for interactive sample
    /// data, but must not participate in remote quota fan-outs.
    nonisolated var isRemoteInterviewFetchEligible: Bool {
        !isMock && isUsableSyncedCredential
    }

    /// The server URL to talk to: the account's override when set and parseable,
    /// otherwise the standard hosted endpoint.
    var resolvedBaseURL: URL {
        baseURLOverride ?? CoderPadClient.defaultBaseURL
    }

    /// The canonical identity of the URL override, or nil when the account uses
    /// the hosted default. Nonisolated (unlike `serverIdentity`, whose hosted
    /// fallback is MainActor-bound) so backend comparisons can run off-actor (#1156).
    nonisolated var overrideServerIdentity: String? {
        baseURLOverride.map(Self.serverIdentity(of:))
    }

    /// The resolved server URL reduced to a canonical identity for duplicate-account
    /// detection: scheme and host folded to lowercase, a default port (80/443)
    /// dropped, and trailing slashes removed, so cosmetic spellings of the same
    /// origin (`https://Example.com:443/` vs `https://example.com`) compare
    /// equal (#850).
    var serverIdentity: String {
        Self.serverIdentity(of: resolvedBaseURL)
    }

    nonisolated static func serverIdentity(of url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if let port = components.port,
           (components.scheme == "https" && port == 443) || (components.scheme == "http" && port == 80) {
            components.port = nil
        }
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    /// Whether `ownerEmail` (a pad or question owner) belongs to this account's user,
    /// ignoring case and surrounding whitespace but preserving the exact mailbox local
    /// part. This backs "my pads"/"my questions" and the Dock badge. Guards against an
    /// empty account email so a draft account (or a pad with no owner) never matches.
    func owns(_ ownerEmail: String) -> Bool {
        !userEmail.isEmpty && ownerEmail.canonicalOwnerEmail == userEmail.canonicalOwnerEmail
    }

    /// Email of the signed-in demo user, who owns several of the mock pads and
    /// questions — so the demo account's "My Pads"/"My Questions" defaults return
    /// real results, and the account satisfies the required-email rule. Sourced
    /// from `MockFixtures` so the account and the fake API agree on who "you" are.
    static let demoUserEmail = MockFixtures.demoUserEmail

    static func demo() -> Self {
        Self(name: MockFixtures.orgName, apiKey: "demo", isMock: true, userEmail: demoUserEmail)
    }

    /// Sentinel key marking the "bad key" demo: a mock account whose in-process
    /// server answers 401 for every request, so the unauthorized banner and error
    /// states can be demoed without a real revoked key.
    static let badKeyMockKey = "demo-bad-key"

    static func demoBadKey() -> Self {
        Self(name: "Demo (bad key)", apiKey: badKeyMockKey, isMock: true, userEmail: demoUserEmail)
    }

    /// Whether this is the bad-key demo, as opposed to the mock-data demo.
    var isBadKeyDemo: Bool {
        isMock && apiKey == Self.badKeyMockKey
    }

    var normalizedForStorage: Self {
        var account = self
        account.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return account
    }

    /// A sandbox demo the user can summon by typing a magic word into the account
    /// editor's API-key field, the discoverable replacement for the old
    /// `wand.and.stars` menu (#549): `demo` adds the mock-data demo, `baddemo` the
    /// revoked-key demo. Mapping the typed word here (rather than reusing each
    /// account's own sentinel key) keeps the user-facing magic words independent of
    /// the internal `badKeyMockKey`.
    enum DemoMagicKey {
        case mockData
        case badKey

        init?(typedKey: String) {
            switch typedKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "demo": self = .mockData
            case "baddemo": self = .badKey
            default: return nil
            }
        }
    }

    /// The API client this account talks to: the in-process mock for demo accounts
    /// (answering 401 for the bad-key demo), otherwise the live hosted client.
    ///
    /// Memoized per set of credentials. Clients are built inside `body` — the section
    /// content rebuilt one on every render pass, so each search keystroke allocated a
    /// fresh REST transport stack (#2111). Two clients built from the same key and
    /// server are interchangeable, so reuse changes nothing but the allocation.
    func makeClient() -> CoderPadClient {
        guard isMock else {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let server = resolvedBaseURL
            return ClientMemo.client(.init(apiKey: key, baseURL: server, isUnauthorizedMock: false)) {
                .live(apiKey: key, baseURL: server)
            }
        }

        // Key the mock client by the account's own apiKey so the good demo ("demo")
        // and the bad-key demo ("demo-bad-key") have distinct client identities. They
        // otherwise share the default "demo" key, which collides in caches keyed by
        // client identity (server + key) — e.g. OrganizationCacheStore (#374) would
        // serve the good demo's cached org to the bad-key client after the good one
        // had loaded, instead of letting the bad key 401.
        return ClientMemo.client(.init(apiKey: apiKey, baseURL: nil, isUnauthorizedMock: isBadKeyDemo)) {
            .mock(unauthorized: isBadKeyDemo, key: apiKey)
        }
    }

    /// The CoderPad **Screen** client this account talks to, or `nil` when a real
    /// account has no Screen key — so Interview-only accounts simply have no Screen.
    /// Demo/mock accounts get the in-process mock Screen client (answering 401 for the
    /// bad-key demo) so the demo exercises the full Screen UI with fixture data. Screen
    /// is additive to the Interview `apiKey`; for a real account the client is pointed at
    /// the US or EU server per `screenRegion`.
    /// Whether this account has Screen credentials, without building a client.
    ///
    /// The sidebar, the phone tab set, and `AppSection.navigable` all asked this by
    /// calling `makeScreenClient()` and testing for nil — constructing a whole client
    /// per account, during body evaluation, on every render (#2257).
    var hasScreenAccess: Bool {
        if isMock { return true }

        return !(screenApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    func makeScreenClient() -> ScreenClient? {
        if isMock {
            return .mock(unauthorized: isBadKeyDemo)
        }

        let trimmed = screenApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        return .live(apiKey: trimmed, baseURL: screenRegion.baseURL)
    }
}
