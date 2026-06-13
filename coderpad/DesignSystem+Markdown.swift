//
//  DesignSystem+Markdown.swift
//  coderpad
//

import MarkdownUI
import SwiftUI

// MARK: - MarkdownText

/// Renders GitHub-flavored Markdown via swift-markdown-ui, themed to match the
/// app's typography. Call sites are unchanged: `MarkdownText(raw)`.
struct MarkdownText: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        if raw.isEmpty {
            Text("(empty)").foregroundStyle(.secondary)
        } else {
            Markdown(raw)
                .markdownTheme(.coderpad)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Theme {
    /// Approximates the app's previous hand-rolled Markdown styling: bold
    /// headings, monospaced inline/code blocks, and a subtle code-block fill.
    static let coderpad = Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.5))
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.3))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.15))
                }
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.9))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.subtleStroke.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .markdownMargin(top: .em(0.5), bottom: .em(0.5))
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
