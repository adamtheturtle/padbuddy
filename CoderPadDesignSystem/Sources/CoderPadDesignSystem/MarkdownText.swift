//
//  MarkdownText.swift
//  CoderPadDesignSystem
//
//  Generic GitHub-flavored Markdown renderer extracted from the app (#377). Domain-free,
//  so the HackerRank app can reuse it.
//

import SwiftUI
import Textual

/// Renders GitHub-flavored Markdown via Textual, themed to match the app's
/// typography. Call sites are unchanged: `MarkdownText(raw)`.
///
/// Textual's default block styles (sized/bold headings, monospaced inline and
/// fenced code with a subtle fill, tables) already approximate the app's look,
/// and `StructuredText` honors the ambient SwiftUI `.font`/`.foregroundStyle`,
/// so we lean on the defaults rather than carrying a hand-rolled theme.
public struct MarkdownText: View {
    let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public var body: some View {
        if raw.isEmpty {
            Text("(empty)").foregroundStyle(.secondary)
        } else {
            StructuredText(markdown: raw)
                .textual.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
