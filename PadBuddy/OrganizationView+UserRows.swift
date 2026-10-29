//
//  OrganizationView+UserRows.swift
//  coderpad
//
//  Split from OrganizationView.swift to keep it within the lint length limit:
//  the per-user row/card views for the Users section moved here.
//

import SwiftUI

nonisolated struct OrganizationUserPresentation: Equatable {
    static let maximumNameLength = 120
    static let maximumEmailLength = 254

    let name: String
    let email: String
    let copyName: String?
    let copyEmail: String?

    init(user: OrganizationUser) {
        let safeEmail = Self.sanitized(user.email, maximumLength: Self.maximumEmailLength)
        let safeName = Self.sanitized(user.name ?? "", maximumLength: Self.maximumNameLength)
        email = safeEmail
        name = safeName.isEmpty ? (safeEmail.isEmpty ? String(localized: "Unknown user") : safeEmail) : safeName
        copyName = safeName.isEmpty ? nil : safeName
        copyEmail = safeEmail.isEmpty ? nil : safeEmail
    }

    private static func sanitized(_ raw: String, maximumLength: Int) -> String {
        ExternalText.singleLine(raw, limit: maximumLength)
    }
}

#if os(macOS)
    struct CompactUserRow: View {
        let user: OrganizationUser

        var body: some View {
            let presentation = OrganizationUserPresentation(user: user)
            HStack(spacing: 12) {
                Text(presentation.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                Text(presentation.email)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .contextMenu { copyActions(presentation) }
        }

        @ViewBuilder
        private func copyActions(_ presentation: OrganizationUserPresentation) -> some View {
            if let name = presentation.copyName {
                Button("Copy Name") { Clipboard.copy(name) }
            }
            if let email = presentation.copyEmail {
                Button("Copy Email") { Clipboard.copy(email) }
            }
        }
    }
#else
    struct TouchUserCard: View {
        let user: OrganizationUser

        var body: some View {
            let presentation = OrganizationUserPresentation(user: user)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(presentation.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.subtleStroke.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contextMenu { copyActions(presentation) }
        }

        @ViewBuilder
        private func copyActions(_ presentation: OrganizationUserPresentation) -> some View {
            if let name = presentation.copyName {
                Button("Copy Name") { Clipboard.copy(name) }
            }
            if let email = presentation.copyEmail {
                Button("Copy Email") { Clipboard.copy(email) }
            }
        }
    }
#endif
