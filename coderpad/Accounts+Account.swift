//
//  Accounts+Account.swift
//  coderpad
//
//  The Account model and its owner-email canonicalization.
//

import Foundation
import SwiftUI

extension String {
    /// This email address reduced to a canonical mailbox form for ownership checks:
    /// trimmed, lowercased, with any plus-addressing tag removed. People route pads to
    /// one mailbox via sub-addresses (`hello+cursor@acme.co`), and CoderPad records the
    /// alias verbatim as the owner, so folding the `+tag` lets the app still recognize
    /// those as the account user's. Only the explicit `+tag` convention is folded; dots
    /// and other provider-specific quirks are left untouched.
    var canonicalOwnerEmail: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = trimmed.firstIndex(of: "@") else { return trimmed }

        let local = trimmed[..<atIndex]
        guard let plus = local.firstIndex(of: "+") else { return trimmed }

        return String(local[..<plus]) + trimmed[atIndex...]
    }
}

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool
    /// The email of the org member this key belongs to, used to show "my" pads.
    /// The CoderPad API doesn't expose the key's owner, so the user picks it when
    /// validating the key — and saving is gated on it (see `canSave`) — so a
    /// persisted account always has one, matching the org-users API where email is
    /// non-optional. A persisted account without one is invalid and dropped on load
    /// (see `init(from:)`). Empty only for an in-progress draft before the owner is
    /// picked.
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

    init(name: String, apiKey: String, id: UUID = UUID(), isMock: Bool = false,
         userEmail: String = "", baseURL: String? = nil,
         iconSymbol: String? = nil, tintHex: String? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
        self.userEmail = userEmail
        self.baseURL = baseURL
        self.iconSymbol = iconSymbol
        self.tintHex = tintHex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, isMock, userEmail, baseURL, iconSymbol, tintHex
    }

    /// Custom decoding to enforce that a persisted account carries a user email: it's
    /// required to save (see `canSave`), so a stored account without one is invalid.
    /// Throwing here drops that single account on load (the store decodes elements
    /// leniently — see `loadAccounts`) rather than corrupting an otherwise-good account.
    /// Encoding stays synthesized.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        isMock = try container.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
        let email = try container.decodeIfPresent(String.self, forKey: .userEmail) ?? ""
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .userEmail, in: container,
                debugDescription: "Account has no user email; treated as invalid and skipped."
            )
        }

        userEmail = email
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        tintHex = try container.decodeIfPresent(String.self, forKey: .tintHex)
    }

    /// The curated SF Symbols offered for an account's avatar. Deliberately small
    /// and generic so the picker stays a quick visual choice rather than a search
    /// through the full symbol library.
    static let iconSymbolChoices = [
        "building.2.fill", "briefcase.fill", "person.2.fill", "house.fill",
        "star.fill", "flag.fill", "hammer.fill", "globe.americas.fill"
    ]

    /// The user-chosen avatar tint parsed from `tintHex`, or `nil` when unset or
    /// unparseable — leaving the default tint to apply.
    var tintColor: Color? {
        guard let tintHex, let color = Color(hex: tintHex) else { return nil }

        return color
    }

    /// The fallback tint when no custom color is chosen: purple for demo accounts,
    /// the app accent for real ones.
    var defaultTint: Color {
        isMock ? .purple : .accentColor
    }

    /// The tint to draw this account's avatar with: the custom color when set,
    /// otherwise `defaultTint`.
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

    /// The server URL to talk to: the account's override when set and parseable,
    /// otherwise the standard hosted endpoint.
    var resolvedBaseURL: URL {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let host = url.host, !host.isEmpty {
            return url
        }
        return CoderPadClient.defaultBaseURL
    }

    /// Whether `ownerEmail` (a pad or question owner) belongs to this account's user,
    /// folding case and plus-addressing so an item owned via a sub-address alias
    /// (`hello+cursor@acme.co`) still counts as the base mailbox (`hello@acme.co`).
    /// This backs "my pads"/"my questions" and the Dock badge. Guards against an
    /// empty account email so a draft account (or a pad with no owner) never matches.
    func owns(_ ownerEmail: String) -> Bool {
        !userEmail.isEmpty && ownerEmail.canonicalOwnerEmail == userEmail.canonicalOwnerEmail
    }

    /// Email of the mock data's "Demo User", who owns several of the mock pads and
    /// questions — so the demo account's "My Pads"/"My Questions" defaults return
    /// real results, and the account satisfies the required-email rule.
    static let demoUserEmail = "demo@example.com"

    static func demo() -> Self {
        Self(name: "Demo (mock data)", apiKey: "demo", isMock: true, userEmail: demoUserEmail)
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

    /// The API client this account talks to: the in-process mock for demo accounts
    /// (answering 401 for the bad-key demo), otherwise the live hosted client.
    func makeClient() -> CoderPadClient {
        guard isMock else {
            return .live(apiKey: apiKey, baseURL: resolvedBaseURL)
        }

        return .mock(unauthorized: isBadKeyDemo)
    }

    /// A draft account pre-filled from the `CODERPAD_API_KEY` (and optional
    /// `CODERPAD_USER_EMAIL`) env vars set in the scheme's Run action, or `nil`
    /// when no key is present. Debug-only convenience so testing against real
    /// data via the Add Account button doesn't mean re-pasting the key each run;
    /// option-click the button to fill from this. Env vars are readable under the
    /// App Sandbox, unlike a home-directory dotfile — keep that scheme non-shared
    /// (xcuserdata) so the key never lands in git.
    static func fromDevEnvironment() -> Self? {
        #if DEBUG
            let env = ProcessInfo.processInfo.environment
            guard let rawKey = env["CODERPAD_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawKey.isEmpty else { return nil }

            let email = env["CODERPAD_USER_EMAIL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Self(name: "Dev (env key)", apiKey: rawKey, userEmail: email)
        #else
            return nil
        #endif
    }
}
