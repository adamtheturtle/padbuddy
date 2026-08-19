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
    public static let renderingLimit = 100_000
    public static let plainTextFallbackLimit = 20000
    public static let plainTextFallbackWorkLimit = 1_000_000
    let raw: String
    let linkHandler: @MainActor (URL) -> OpenURLAction.Result

    /// Creates a renderer with an explicit link-opening boundary. The default accepts
    /// ordinary web links but rejects credentials, fragments containing control data,
    /// and custom schemes. Callers handling especially sensitive content can intercept
    /// every URL to enforce a host allowlist or return `.discarded` for all links.
    @preconcurrency public init(
        _ raw: String,
        linkHandler: @escaping @MainActor (URL) -> OpenURLAction.Result = Self.safeLinkAction
    ) {
        self.raw = Self.boundedRenderingInput(raw)
        self.linkHandler = linkHandler
    }

    public var body: some View {
        Group {
            if raw.isEmpty {
                Text("(empty)").foregroundStyle(.secondary)
            } else {
                StructuredText(markdown: raw)
                    .textual.textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.openURL, OpenURLAction(handler: linkHandler))
    }

    public static func safeLinkAction(_ url: URL) -> OpenURLAction.Result {
        isSafeRemoteLink(url) ? .systemAction(url) : .discarded
    }

    public static func isSafeRemoteLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.user == nil, url.password == nil, url.host != nil else { return false }

        let serialized = url.absoluteString
        guard !containsInvisibleURLScalar(serialized),
              let decoded = serialized.removingPercentEncoding,
              !containsInvisibleURLScalar(decoded) else { return false }

        return true
    }

    private static func containsInvisibleURLScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned:
                true
            default:
                false
            }
        }
    }

    /// Produces a bounded readable fallback for callers that cannot present the
    /// structured renderer. Rendering itself uses Textual on every supported platform
    /// so GitHub-flavored constructs have identical semantics on macOS and iOS (#1340).
    public static func plainTextFallback(_ raw: String) -> String {
        let input = boundedUTF8Prefix(raw, limit: Self.plainTextFallbackWorkLimit).value
        var safe = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format where scalar.value != 0x200C && scalar.value != 0x200D:
                continue
            case .control, .privateUse, .surrogate, .unassigned:
                safe.append(" ")
            default:
                safe.append(scalar)
            }
        }
        let normalized = String(safe)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "(empty)" }

        return String(normalized.prefix(Self.plainTextFallbackLimit))
    }

    public static func boundedRenderingInput(_ raw: String) -> String {
        let bounded = boundedUTF8Prefix(raw, limit: Self.renderingLimit)
        guard bounded.truncated else { return raw }

        return bounded.value + "\n\n_Content truncated for display._"
    }

    private static func boundedUTF8Prefix(_ raw: String, limit: Int) -> (value: String, truncated: Bool) {
        let inspectedBytes = raw.utf8.prefix(limit + 1)
        guard inspectedBytes.count > limit else { return (raw, false) }

        var bytes = Array(inspectedBytes.prefix(limit))
        var bounded = String(bytes: bytes, encoding: .utf8)
        while bounded == nil, !bytes.isEmpty {
            bytes.removeLast()
            bounded = String(bytes: bytes, encoding: .utf8)
        }
        return (bounded ?? "", true)
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
