//
//  MarkdownText.swift
//  CoderPadDesignSystem
//
//  Generic GitHub-flavored Markdown renderer extracted from the app (#377). Domain-free,
//  so the HackerRank app can reuse it.
//

import SwiftUI
#if !os(iOS)
    import Textual
#endif

/// Renders GitHub-flavored Markdown via Textual, themed to match the app's
/// typography. Call sites are unchanged: `MarkdownText(raw)`.
///
/// Textual's default block styles (sized/bold headings, monospaced inline and
/// fenced code with a subtle fill, tables) already approximate the app's look,
/// and `StructuredText` honors the ambient SwiftUI `.font`/`.foregroundStyle`,
/// so we lean on the defaults rather than carrying a hand-rolled theme.
public struct MarkdownText: View {
    public static let renderingLimit = 100_000
    public static let plainTextFallbackLimit = 20000
    let raw: String

    public init(_ raw: String) {
        self.raw = Self.boundedRenderingInput(raw)
    }

    public var body: some View {
        if raw.isEmpty {
            Text("(empty)").foregroundStyle(.secondary)
        } else {
            #if os(iOS)
                iosMarkdown
            #else
                StructuredText(markdown: raw)
                    .textual.textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
    }

    @ViewBuilder
    private var iosMarkdown: some View {
        if let attributed = try? AttributedString(markdown: raw) {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Formatting unavailable — showing plain text", systemImage: "text.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.plainTextFallback(raw))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    public static func plainTextFallback(_ raw: String) -> String {
        let safe = raw.map { character -> Character in
            let categories = character.unicodeScalars.map(\.properties.generalCategory)
            let containsForbidden = categories.contains {
                switch $0 {
                case .control, .privateUse, .surrogate, .unassigned: true
                default: false
                }
            }
            let isOnlyFormatting = categories.allSatisfy { $0 == .format }
            return containsForbidden || isOnlyFormatting ? " " : character
        }
        let normalized = String(safe)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "(empty)" }

        return String(normalized.prefix(Self.plainTextFallbackLimit))
    }

    public static func boundedRenderingInput(_ raw: String) -> String {
        let prefix = raw.prefix(Self.renderingLimit + 1)
        guard prefix.count > Self.renderingLimit else { return raw }

        return String(prefix.prefix(Self.renderingLimit))
            + "\n\n_Content truncated for display._"
    }
}

#Preview("MarkdownText") {
    ScrollView {
        MarkdownText(
            """
            # Reverse a Linked List
            Implement a function that reverses a singly linked list **in place**.

            ## Requirements
            - Run in `O(n)` time and `O(1)` extra space
            - Handle the *empty list* and single-node cases
            - Return the new head

            ### Example
            Given `1 -> 2 -> 3`, return `3 -> 2 -> 1`.

            1. Walk the list
            2. Re-point each `next`
            3. Track the previous node

            ```swift
            func reverse(_ head: Node?) -> Node? {
                var prev: Node? = nil
                var node = head
                while let current = node {
                    node = current.next
                    current.next = prev
                    prev = current
                }
                return prev
            }
            ```

            | Case | Input | Output |
            | --- | --- | --- |
            | Empty | `nil` | `nil` |
            | Single | `1` | `1` |
            """
        )
        .padding()
    }
    .frame(width: 460, height: 640)
}
