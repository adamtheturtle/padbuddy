//
//  OwnerPickerMembers.swift
//  coderpad
//

import Foundation

/// Prepared organization membership reused by the owner picker's labels, rows,
/// and custom-address validation. Building it only when inputs change keeps body
/// evaluation from repeatedly scanning and sorting the same member list (#2129).
struct OwnerPickerMembers {
    let rows: [OrganizationUser]
    private let namesByEmail: [String: String]
    private let emails: Set<String>

    init(users: [OrganizationUser], keyOwnerEmail: String?) {
        let selfEmail = keyOwnerEmail?.trimmingCharacters(in: .whitespaces).lowercased()
        var names: [String: String] = [:]
        var knownEmails = Set<String>()
        var uniqueRows: [OrganizationUser] = []
        uniqueRows.reserveCapacity(users.count)

        for user in users {
            let key = user.email.lowercased()
            let isFirst = knownEmails.insert(key).inserted
            if let name = user.name, !name.isEmpty {
                names[key] = name
            }
            guard key != selfEmail, isFirst else {
                continue
            }

            uniqueRows.append(user)
        }
        rows = uniqueRows.sorted {
            ($0.name.flatMap { $0.isEmpty ? nil : $0 } ?? $0.email)
                .localizedCaseInsensitiveCompare($1.name.flatMap { $0.isEmpty ? nil : $0 } ?? $1.email)
                == .orderedAscending
        }
        namesByEmail = names
        emails = knownEmails
    }

    func name(for email: String) -> String? {
        namesByEmail[email.lowercased()]
    }

    func contains(email: String) -> Bool {
        emails.contains(email.lowercased())
    }
}
