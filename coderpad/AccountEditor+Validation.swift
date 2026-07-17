//
//  AccountEditor+Validation.swift
//  coderpad
//
//  Helpers for tying account validation results to the exact credentials that
//  produced them, split out of AccountEditor+Logic.swift to keep that file short.
//

import Foundation

extension AccountEditor {
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

    func applyValidatedOrganization(
        _ org: Organization,
        client: CoderPadClient,
        fingerprint: ValidationFingerprint
    ) async -> Bool {
        guard validationStillMatches(fingerprint) else { return false }

        orgUsers = org.users
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.name = org.organizationName
        }
        // Pre-select the signed-in user's email. The default /api/pads/ endpoint
        // is scoped to the API key owner, so the dominant owner email on their pads
        // is "you". Detect it directly, then fall back to the single-user org case.
        if draft.userEmail.isEmpty {
            let detected = await detectUserEmail(client: client)
            guard validationStillMatches(fingerprint) else { return false }

            if let detected, draft.userEmail.isEmpty {
                draft.userEmail = detected
            } else if draft.userEmail.isEmpty, org.users.count == 1 {
                draft.userEmail = org.users.first?.email ?? ""
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
