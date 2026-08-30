//
//  AccountEditor+Validation.swift
//  coderpad
//
//  Helpers for tying account validation results to the exact credentials that
//  produced them, split out of AccountEditor+Logic.swift to keep that file short.
//

import Foundation

extension AccountEditor {
    static func normalizedCredential(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

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
            apiKey: Self.normalizedCredential(draft.apiKey),
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

    static func emailBelongsToValidatedOrganization(_ email: String, users: [OrganizationUser]) -> Bool {
        let normalized = EmailValidation.normalized(email)
        guard EmailValidation.isPlausibleAddress(normalized) else { return false }

        return users.contains {
            EmailValidation.normalized($0.email).caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    func emailIdentityChanged() {
        if validatedOrgName != nil {
            validation = Self.emailBelongsToValidatedOrganization(draft.userEmail, users: orgUsers)
                ? .valid
                : .invalid(String(localized: "Choose an email from the validated organization."))
        }
        commitLiveEdit()
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
        // Never infer the key owner from shared/team pad frequency. Only an
        // unambiguous validated member list is safe to select automatically (#1401).
        if draft.userEmail.isEmpty,
           let owner = Self.automaticOwnerEmail(userEmails: org.users.map(\.email)) {
            draft.userEmail = owner
        }
        validation = .valid
        validatedOrgName = org.organizationName

        let warning = await missingScopesWarning(client: client)
        guard validationStillMatches(fingerprint) else { return false }

        scopeWarning = warning
        return true
    }
}
