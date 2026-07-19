//
//  AccountEditor+Validation.swift
//  coderpad
//
//  Helpers for tying account validation results to the exact credentials that
//  produced them, split out of AccountEditor+Logic.swift to keep that file short.
//

import Foundation

extension AccountEditor {
    struct ValidationThrottle {
        var failureCount = 0
        var isCoolingDown = false
        var task: Task<Void, Never>?
    }

    func beginValidationCooldown() {
        validationThrottle.failureCount += 1
        validationThrottle.isCoolingDown = true
        validationThrottle.task?.cancel()
        let delay = Self.validationCooldown(afterFailures: validationThrottle.failureCount)
        validationThrottle.task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            validationThrottle.isCoolingDown = false
            validationThrottle.task = nil
        }
    }

    func resetValidationThrottle() {
        validationThrottle.task?.cancel()
        validationThrottle = ValidationThrottle()
    }

    static func validationCooldown(afterFailures failures: Int) -> Duration {
        let exponent = min(max(failures - 1, 0), 4)
        return .seconds(min(2 * Int(pow(2, Double(exponent))), 30))
    }

    struct ValidationFingerprint: Equatable {
        let apiKey: String
        let baseURL: URL
    }

    var currentValidationFingerprint: ValidationFingerprint {
        ValidationFingerprint(
            apiKey: draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: draft.resolvedBaseURL
        )
    }

    func validationStillMatches(_ fingerprint: ValidationFingerprint) -> Bool {
        currentValidationFingerprint == fingerprint
    }

    static func validatedOwnerEmail(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let normalized = EmailValidation.normalized(raw)
        return EmailValidation.isPlausibleAddress(normalized) ? normalized : nil
    }

    static func shouldAutofillValidatedName(
        _ currentName: String,
        currentGeneration: Int,
        validatedGeneration: Int
    ) -> Bool {
        currentGeneration == validatedGeneration
            && currentName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func hasUsableOrganizationIdentity(name: String, userEmails: [String]) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && userEmails.contains { validatedOwnerEmail($0) != nil }
    }

    func applyValidatedOrganization(
        _ org: Organization,
        client: CoderPadClient,
        fingerprint: ValidationFingerprint,
        nameGeneration: Int
    ) async -> Bool {
        guard validationStillMatches(fingerprint) else { return false }
        guard Self.hasUsableOrganizationIdentity(
            name: org.organizationName,
            userEmails: org.users.map(\.email)
        ) else {
            validation = .invalid(String(localized: "The organization response is missing its name or members."))
            return false
        }

        orgUsers = org.users
        if Self.shouldAutofillValidatedName(
            draft.name,
            currentGeneration: nameEditGeneration,
            validatedGeneration: nameGeneration
        ) {
            draft.name = org.organizationName
        }
        // Pre-select the signed-in user's email. The default /api/pads/ endpoint
        // is scoped to the API key owner, so the dominant owner email on their pads
        // is "you". Detect it directly, then fall back to the single-user org case.
        if draft.userEmail.isEmpty {
            let detected = await detectUserEmail(client: client)
            guard validationStillMatches(fingerprint) else { return false }

            if let detected = Self.validatedOwnerEmail(detected), draft.userEmail.isEmpty {
                draft.userEmail = detected
            } else if draft.userEmail.isEmpty, org.users.count == 1 {
                draft.userEmail = Self.validatedOwnerEmail(org.users.first?.email) ?? ""
            }
        }
        validation = .valid
        validatedOrgName = org.organizationName

        let warning = await missingScopesWarning(client: client)
        guard validationStillMatches(fingerprint) else { return false }

        scopeWarning = warning
        return true
    }
}
