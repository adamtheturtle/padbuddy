//
//  OrganizationView+UserRows.swift
//  coderpad
//
//  Split from OrganizationView.swift to keep it within the lint length limit:
//  the per-user row/card views for the Users section moved here.
//

import SwiftUI

#if os(macOS)
    struct CompactUserRow: View {
        let user: OrganizationUser

        private var displayName: String {
            user.name ?? user.email
        }

        var body: some View {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    AvatarCircle(label: displayName, diameter: 24)
                    Text(displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                Text(user.email)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
    }
#else
    struct TouchUserCard: View {
        let user: OrganizationUser

        private var displayName: String {
            user.name ?? user.email
        }

        var body: some View {
            HStack(spacing: 10) {
                AvatarCircle(label: displayName, diameter: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.subtleStroke.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
#endif
