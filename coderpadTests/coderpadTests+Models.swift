//
//  coderpadTests+Models.swift
//  coderpadTests
//

@testable import coderpad
import Foundation
import SwiftUI
import Testing

@Suite("Question sort field/direction")
struct QuestionSortTests {
    @Test func `each sort maps to the expected field`() {
        #expect(QuestionSort.lastUsedDesc.field == .lastUsed)
        #expect(QuestionSort.lastUsedAsc.field == .lastUsed)
        #expect(QuestionSort.usedDesc.field == .used)
        #expect(QuestionSort.usedAsc.field == .used)
        #expect(QuestionSort.titleAsc.field == .title)
        #expect(QuestionSort.titleDesc.field == .title)
    }

    @Test func `directions list the field's two sorts, default first`() {
        #expect(QuestionSort.directions(for: .lastUsed).map(\.sort) == [.lastUsedDesc, .lastUsedAsc])
        #expect(QuestionSort.directions(for: .used).map(\.sort) == [.usedDesc, .usedAsc])
        #expect(QuestionSort.directions(for: .title).map(\.sort) == [.titleAsc, .titleDesc])
    }

    @Test func `withField keeps the current direction slot`() {
        // Slot 0 (default) stays slot 0 across fields.
        #expect(QuestionSort.lastUsedDesc.withField(.title) == .titleAsc)
        #expect(QuestionSort.titleAsc.withField(.used) == .usedDesc)
        // Slot 1 (reverse) stays slot 1.
        #expect(QuestionSort.lastUsedAsc.withField(.title) == .titleDesc)
        #expect(QuestionSort.titleDesc.withField(.lastUsed) == .lastUsedAsc)
        // Switching to the same field is a no-op.
        #expect(QuestionSort.usedAsc.withField(.used) == .usedAsc)
    }
}

@Suite("Language helpers")
struct LanguageHelperTests {
    @Test(arguments: [
        ("python3", "Python 3"),
        ("python2", "Python 2"),
        ("javascript", "JavaScript"),
        ("typescript", "TypeScript"),
        ("nodejs", "Node.js"),
        ("cpp", "C++"),
        ("csharp", "C#"),
        ("objective-c", "Objective-C"),
        ("postgresql", "PostgreSQL"),
        ("fsharp", "F#")
    ])
    func `languageDisplayName maps known codes to friendly names`(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test(arguments: [
        ("multifile_java", "Java Project"),
        ("Multifile_java", "Java Project"),
        ("multifile_python3", "Python 3 Project"),
        ("multifile_nodejs", "Node.js Project")
    ])
    func `languageDisplayName names multifile project environments`(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test(arguments: [
        ("zig", "Zig"),
        ("", "")
    ])
    func `languageDisplayName capitalizes unknown codes`(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }
}

@Suite("Account round-trip")
struct AccountRoundTripTests {
    @Test
    func `account encodes/decodes through JSON without loss`() throws {
        let original = Account(name: "Production", apiKey: "secret-key", isMock: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.apiKey == original.apiKey)
        #expect(decoded.isMock == original.isMock)
    }

    @Test
    func `demo account survives the round-trip with isMock = true`() throws {
        let demo = Account.demo()
        let data = try JSONEncoder().encode(demo)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.isMock == true)
        #expect(decoded.name == "Demo (mock data)")
    }

    @Test
    func `demo accounts carry the required user email`() {
        #expect(Account.demo().userEmail == Account.demoUserEmail)
        #expect(Account.demoBadKey().userEmail == Account.demoUserEmail)
    }
}

@Suite("What's New gating", .serialized)
struct WhatsNewTests {
    private static let key = "lastSeenWhatsNewVersion"

    private func withCleanDefault<T>(_ block: () throws -> T) rethrows -> T {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }
        return try block()
    }

    @Test
    func `shouldShow returns true on clean install`() {
        withCleanDefault {
            #expect(WhatsNew.shouldShow() == true)
        }
    }

    @Test
    func `markSeen suppresses future prompts for the same version`() {
        withCleanDefault {
            WhatsNew.markSeen()
            #expect(WhatsNew.shouldShow() == false)
        }
    }

    @Test
    func `an older recorded version still triggers the prompt`() {
        withCleanDefault {
            UserDefaults.standard.set("0.1", forKey: Self.key)
            #expect(WhatsNew.shouldShow() == true)
        }
    }

    @Test
    func `the gate is keyed on the live app version, not a hardcoded constant`() {
        withCleanDefault {
            // markSeen must record exactly the version the gate compares against, so
            // a MARKETING_VERSION bump (which changes WhatsNew.version) re-shows the
            // sheet without anyone editing a second constant.
            #expect(!WhatsNew.version.isEmpty)
            #expect(WhatsNew.current.version == WhatsNew.version)
            WhatsNew.markSeen()
            #expect(UserDefaults.standard.string(forKey: Self.key) == WhatsNew.version)

            // Recording any other version re-arms the prompt.
            UserDefaults.standard.set(WhatsNew.version + "-old", forKey: Self.key)
            #expect(WhatsNew.shouldShow() == true)
        }
    }
}

@Suite("Quota decoder")
struct QuotaDecoderTests {
    @Test
    func `parses dates with timezone offset and fractional seconds`() throws {
        let json = """
        {
          "status": "OK",
          "trial_expires_at": "2025-04-24T17:00:00.000-07:00",
          "pads_used": 57,
          "quota_reset_at": "2026-05-29T00:05:00.000-07:00",
          "unlimited": true,
          "overages_enabled": false
        }
        """
        let quota = try CoderPadClient.decoder.decode(Quota.self, from: Data(json.utf8))
        #expect(quota.padsUsed == 57)
        #expect(quota.unlimited == true)
        #expect(quota.overagesEnabled == false)
        #expect(quota.trialExpiresAt != nil)
        #expect(quota.quotaReset != nil)
    }
}

@Suite("App appearance")
struct AppAppearanceTests {
    @Test(arguments: [
        (AppAppearance.system, "system"),
        (AppAppearance.light, "light"),
        (AppAppearance.dark, "dark")
    ])
    func `raw values are stable (they back the stored preference)`(appearance: AppAppearance, rawValue: String) {
        #expect(appearance.rawValue == rawValue)
    }

    @Test(arguments: [
        (AppAppearance.system, ColorScheme?.none),
        (AppAppearance.light, .light),
        (AppAppearance.dark, .dark)
    ])
    func `maps to the color scheme it forces, nil for system`(appearance: AppAppearance, scheme: ColorScheme?) {
        #expect(appearance.colorScheme == scheme)
    }

    @Test
    func `every case has a non-empty label`() {
        #expect(AppAppearance.allCases.allSatisfy { !$0.label.isEmpty })
    }
}

// Serialized: these read and mutate process-wide UserDefaults under the
// `general.*` keys, so concurrent runs would clobber each other's values.
@Suite("General settings", .serialized)
struct GeneralSettingsTests {
    private static let keys = [
        GeneralSettings.Key.appearance,
        GeneralSettings.Key.hideDockIcon,
        GeneralSettings.Key.refreshSeconds
    ]

    /// Snapshots the `general.*` defaults, clears them, runs the block, then restores
    /// whatever was there before so the test leaves no trace.
    private func withCleanDefaults<T>(_ block: () throws -> T) rethrows -> T {
        let saved = Self.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        for key in Self.keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            for (key, value) in saved {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        return try block()
    }

    @Test
    func `refreshSeconds falls back to the default when unset`() {
        withCleanDefaults {
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.defaultRefreshSeconds)
            #expect(GeneralSettings.refreshInterval == .seconds(GeneralSettings.defaultRefreshSeconds))
        }
    }

    @Test
    func `refreshSeconds passes a valid stored value through`() {
        withCleanDefaults {
            UserDefaults.standard.set(120, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == 120)
            #expect(GeneralSettings.refreshInterval == .seconds(120))
        }
    }

    @Test
    func `refreshSeconds clamps below the minimum and above the maximum`() {
        withCleanDefaults {
            UserDefaults.standard.set(1, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.minRefreshSeconds)

            UserDefaults.standard.set(99999, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.maxRefreshSeconds)
        }
    }

    @Test
    func `appearance defaults to system and reads back a stored choice`() {
        withCleanDefaults {
            #expect(GeneralSettings.appearance == .system)

            UserDefaults.standard.set("dark", forKey: GeneralSettings.Key.appearance)
            #expect(GeneralSettings.appearance == .dark)

            // An unrecognized stored value falls back to system rather than crashing.
            UserDefaults.standard.set("chartreuse", forKey: GeneralSettings.Key.appearance)
            #expect(GeneralSettings.appearance == .system)
        }
    }

    @Test
    func `hideDockIcon defaults to false and reflects a stored true`() {
        withCleanDefaults {
            #expect(GeneralSettings.hideDockIcon == false)
            UserDefaults.standard.set(true, forKey: GeneralSettings.Key.hideDockIcon)
            #expect(GeneralSettings.hideDockIcon == true)
        }
    }
}

@Suite("CoderPadError messages")
struct CoderPadErrorMessageTests {
    @Test
    func `HTTP errors never leak the raw response body into the message`() throws {
        let error = CoderPadError.http(404, #"{"status":404,"error":"Not Found"}"#)
        let message = try #require(error.errorDescription)
        // The old message dumped the JSON verbatim; the new one must not.
        #expect(!message.contains("{"))
        #expect(!message.contains("status"))
        #expect(message.contains("deleted"))
    }

    @Test
    func `known status codes get a plain-language explanation`() {
        #expect(CoderPadError.http(401, "").errorDescription?.contains("API key") == true)
        #expect(CoderPadError.http(429, "").errorDescription?.contains("rate-limiting") == true)
        #expect(CoderPadError.http(503, "").errorDescription?.contains("server error") == true)
    }

    @Test
    func `an API-supplied message is preferred over a bare HTTP code`() {
        let error = CoderPadError.http(422, #"{"message":"Title can't be blank"}"#)
        #expect(error.errorDescription == "Title can't be blank")
    }

    @Test
    func `transport failures map to plain-language, actionable messages`() {
        #expect(CoderPadError.network(URLError(.notConnectedToInternet)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.networkConnectionLost)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.timedOut)).errorDescription?.contains("timed out") == true)
        #expect(
            CoderPadError.network(URLError(.cannotConnectToHost)).errorDescription?.contains("reach CoderPad") == true
        )
        #expect(CoderPadError.network(URLError(.cannotFindHost)).errorDescription?.contains("reach CoderPad") == true)
        // An unmapped code still gets a useful, non-empty fallback (not a raw URLError dump).
        let fallback = CoderPadError.network(URLError(.badServerResponse)).errorDescription ?? ""
        #expect(fallback.contains("network error"))
        #expect(!fallback.contains("Error Domain"))
    }
}
