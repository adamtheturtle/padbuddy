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
//  The mechanism is SafeURLKit's (#1866); the policy stays here. Two policies rather
//  than one, because the port rules genuinely differ: public history is served on 443
//  only, whilst a self-hosted account is whatever port it was configured on. Folding
//  them into a single policy would mean widening the port rule to cover the account's
//  port and then letting the suffix rules match on it too, which would allow
//  `https://coderpad.io:<account port>/` — an origin nobody approved.
//

import Foundation
import SafeURLKit

nonisolated enum PadHistoryURLValidation {
    /// Exact production origins known to own CoderPad history. Broad suffix rules would
    /// grant every unrelated Firebase project (or CoderPad subdomain) fetch authority;
    /// keeping the project hosts explicit binds history to the service that owns it.
    private static let trustedOrigins = [
        "https://app.coderpad.io",
        "https://eu.app.coderpad.io",
        "https://coderpad-prod.europe-west1.firebasedatabase.app"
    ]

    /// HTTPS on a trusted public origin, standard port only.
    ///
    /// Credentials and fragments are rejected because history metadata is untrusted and
    /// neither belongs in a fetch the app performs (#1749). A query is allowed because
    /// Firebase history URLs legitimately carry one. IP literals, reserved names, and
    /// reserved address ranges are all refused by default.
    private static let trustedOriginPolicy = URLPolicy(
        allowedSchemes: ["https"],
        allowedOrigins: trustedOrigins.compactMap(OriginRule.origin(matching:)),
        portRule: .defaultForScheme
    )

    /// Whether `urlString` may be fetched for pad history: HTTPS on a trusted origin or
    /// on the account's own API origin, and never an IP literal or local name.
    static func isAllowed(_ urlString: String, accountBaseURL: URL) -> Bool {
        if trustedOriginPolicy.allows(urlString) {
            return true
        }
        if firebaseShardPolicy(for: urlString)?.allows(urlString) == true {
            return true
        }
        return accountPolicy(for: accountBaseURL)?.allows(urlString) ?? false
    }

    /// CoderPad's legacy Firebase databases use numbered project hosts. Match that
    /// complete namespace exactly instead of guessing an upper shard number or granting
    /// every project below `firebaseio.com` access.
    private static func firebaseShardPolicy(for urlString: String) -> URLPolicy? {
        guard let host = URLComponents(string: urlString)?.host?.lowercased(),
              host.hasPrefix("coderpad-"), host.hasSuffix(".firebaseio.com")
        else { return nil }

        let shardStart = host.index(host.startIndex, offsetBy: "coderpad-".count)
        let shardEnd = host.index(host.endIndex, offsetBy: -".firebaseio.com".count)
        let shard = host[shardStart ..< shardEnd]
        guard let first = shard.first, first != "0",
              shard.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let parsedHost = try? URLHost.parse(host)
        else { return nil }

        return URLPolicy(
            allowedSchemes: ["https"],
            allowedOrigins: [.origin(scheme: "https", host: parsedHost, port: nil)],
            portRule: .defaultForScheme
        )
    }

    /// HTTPS on exactly the account's own origin.
    ///
    /// The match is on the full origin, so the same host on a different port is another
    /// service on that machine and not the account's API (#1748). The port rule has to
    /// name the account's port explicitly: SafeURLKit checks the port rule before the
    /// origin list and does not combine them, so an origin rule alone would reject
    /// everything.
    ///
    /// The scheme stays HTTPS-only even when the account is configured for plain HTTP,
    /// preserving the behaviour this guard has always had — history is fetched over TLS
    /// or not at all.
    private static func accountPolicy(for accountBaseURL: URL) -> URLPolicy? {
        guard let host = accountBaseURL.host()?.lowercased(), !host.isEmpty,
              let parsedHost = try? URLHost.parse(host)
        else { return nil }

        let scheme = accountBaseURL.scheme?.lowercased()
        let port = accountBaseURL.port ?? (scheme == "http" ? 80 : 443)

        return URLPolicy(
            allowedSchemes: ["https"],
            allowedOrigins: [.origin(scheme: "https", host: parsedHost, port: port)],
            portRule: .allowed([port]),
            // Self-hosted deployments live on internal names - `coderpad.acme.internal` is
            // the case the tests cover - and SafeURLKit treats `.internal` as reserved, so
            // this has to be allowed or self-hosting breaks. It is a narrow widening: the
            // exact-origin rule above still admits precisely one origin, the one the user
            // configured themselves.
            //
            // IP literals and reserved address ranges stay refused, matching what this
            // guard has always done. An account configured against a raw LAN address is
            // therefore still rejected for history fetches; that is arguably inconsistent
            // with allowing `.internal`, but it is the existing behaviour and loosening it
            // is a decision for a separate change, not a side effect of this one.
            allowsSpecialUseHostNames: true
        )
    }
}
