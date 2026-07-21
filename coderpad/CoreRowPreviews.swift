//
//  CoreRowPreviews.swift
//  coderpad
//

#if DEBUG
    import Foundation
    import SwiftUI

    private enum CoreRowPreviewFixtures {
        static let pad: Pad = decode(
            #"""
            {
              "id": "PREVIEW-PAD",
              "title": "Senior Platform Engineer — architecture and systems interview",
              "state": "started",
              "owner_email": "engineer@example.com",
              "language": "typescript",
              "participants": ["Candidate", "Interviewer"],
              "updated_at": "2026-07-21T09:30:00Z"
            }
            """#
        )

        static let question: Question = decode(
            #"""
            {
              "id": 42,
              "title": "Design a resilient distributed task scheduler",
              "owner_email": "engineer@example.com",
              "language": "python3",
              "take_home": true,
              "is_draft": true,
              "author_name": "Ada Lovelace",
              "organization_name": "Preview Organization",
              "updated_at": "2026-07-20T15:00:00Z"
            }
            """#
        )

        @MainActor
        static let account = RowAccount(Account(
            name: "European Engineering Organization",
            apiKey: "preview",
            iconSymbol: "building.2.fill",
            tintHex: "#30B0C7"
        ))

        private static func decode<Value: Decodable>(_ json: String) -> Value {
            do {
                return try CoderPadClient.decoder.decode(Value.self, from: Data(json.utf8))
            } catch {
                preconditionFailure("Invalid core-row preview fixture: \(error)")
            }
        }
    }

    private struct CoreRowPreviewStack: View {
        let width: CGFloat

        var body: some View {
            VStack(spacing: 0) {
                PadRowHostableContent(
                    pad: CoreRowPreviewFixtures.pad,
                    rowAccount: nil,
                    ownerDisplay: "Ada Lovelace",
                    isFavorite: false,
                    onToggleFavorite: {}
                )
                Divider()
                PadRowHostableContent(
                    pad: CoreRowPreviewFixtures.pad,
                    rowAccount: CoreRowPreviewFixtures.account,
                    ownerDisplay: "Ada Lovelace",
                    isFavorite: true,
                    onToggleFavorite: {}
                )
                Divider()
                QuestionRowHostableContent(
                    question: CoreRowPreviewFixtures.question,
                    presentation: nil,
                    rowAccount: CoreRowPreviewFixtures.account,
                    isFavorite: true,
                    onToggleFavorite: {}
                )
            }
            .frame(width: width)
            .background(Color.previewBackground)
        }
    }

    private extension Color {
        static var previewBackground: Color {
            #if os(macOS)
                Color(nsColor: .windowBackgroundColor)
            #else
                Color(uiColor: .systemBackground)
            #endif
        }
    }

    #Preview("Core Rows — Regular") {
        CoreRowPreviewStack(width: 520)
    }

    #Preview("Core Rows — Constrained") {
        CoreRowPreviewStack(width: 300)
    }

    #Preview("Core Rows — Dark") {
        CoreRowPreviewStack(width: 520)
            .preferredColorScheme(.dark)
    }
#endif
