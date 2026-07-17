//
//  PadHistoryURLValidation.swift
//  coderpad
//
//  Client-side SSRF guard for pad file history URLs (#856). The `history` value on a
//  pad environment file is API data, not something the user typed: a compromised or
//  malicious endpoint could point it at localhost, a LAN address, or a cloud metadata
//  service, and the app would fetch it from the user's machine. Only HTTPS URLs on the
//  origins history is actually served from (CoderPad itself and Firebase), or on the
//  account's own API host (self-hosted deployments), are fetched.
//

import Foundation

nonisolated enum PadHistoryURLValidation {
    /// Origins pad history is known to be served from: CoderPad itself and the Firebase
    /// Realtime Database domains its history URLs point at.
    private static let trustedHostSuffixes = ["coderpad.io", "firebaseio.com", "firebasedatabase.app"]

    /// Whether `urlString` may be fetched for pad history: HTTPS on a trusted origin or
    /// on the account's own API host, and never an IP literal or local name.
    static func isAllowed(_ urlString: String, accountBaseURL: URL) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              !isLocalOrIPLiteral(host)
        else { return false }

        if let accountHost = accountBaseURL.host?.lowercased(), host == accountHost { return true }

        return trustedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// IP literals and local names are the classic SSRF targets (127.0.0.1,
    /// 169.254.169.254, ::1, printer.local) and can never be a trusted history origin.
    private static func isLocalOrIPLiteral(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") { return true }
        // IPv6 literals contain colons (URL.host strips the brackets).
        if host.contains(":") { return true }
        // All-digit hosts cover legacy single-integer IPv4 spellings (2130706433)
        // that inet_pton's strict dotted-quad parse would miss.
        if !host.isEmpty, host.allSatisfy(\.isNumber) { return true }
        var ipv4 = in_addr()
        return inet_pton(AF_INET, host, &ipv4) == 1
    }
}
