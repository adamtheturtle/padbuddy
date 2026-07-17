//
//  Resources.swift
//  CoderPadMCPCore
//
//  The MCP resources the server exposes (#517). Resources are addressable, readable
//  context items identified by a `coderpad://` URI. A handful of singletons (quota,
//  organization) are listed directly; pads and questions are exposed as URI templates
//  the client fills in. The URI parsing is pure, so it is unit-tested without a server.
//

import Foundation
import MCP

/// The URI scheme for all CoderPad resources.
public let resourceScheme = "coderpad"

/// Concrete, always-available resources (no parameters), advertised by
/// `resources/list`.
public let staticResources: [Resource] = [
    Resource(
        name: "Pad quota",
        uri: "coderpad://quota",
        description: "The account's pad quota usage.",
        mimeType: "application/json"
    ),
    Resource(
        name: "Organization directory",
        uri: "coderpad://organization",
        description: "The organization's teams and members.",
        mimeType: "application/json"
    )
]

public func staticResources(for accountSet: MCPAccountSet) -> [Resource] {
    guard accountSet.accounts.count > 1 else { return staticResources }

    return accountSet.accounts.flatMap { account in
        let encodedName = resourcePathComponent(account.name)
        return [
            Resource(
                name: "\(account.name) pad quota",
                uri: "coderpad://account/\(encodedName)/quota",
                description: "The pad quota usage for \(account.name).",
                mimeType: "application/json"
            ),
            Resource(
                name: "\(account.name) organization directory",
                uri: "coderpad://account/\(encodedName)/organization",
                description: "The organization teams and members for \(account.name).",
                mimeType: "application/json"
            )
        ]
    }
}

/// URI templates for the parameterized resources, advertised by
/// `resources/templates/list`.
public let resourceTemplates: [Resource.Template] = [
    Resource.Template(
        uriTemplate: "coderpad://pad/{id}",
        name: "Pad",
        description: "A single pad's full detail as JSON. {id} is the pad id / slug.",
        mimeType: "application/json"
    ),
    Resource.Template(
        uriTemplate: "coderpad://pad/{id}/code",
        name: "Pad code",
        description: "Just the code in a pad: each file with its filename, language, and contents.",
        mimeType: "application/json"
    ),
    Resource.Template(
        uriTemplate: "coderpad://question/{id}",
        name: "Question",
        description: "A single question's full detail as JSON. {id} is the numeric question id.",
        mimeType: "application/json"
    )
]

public let accountResourceTemplates: [Resource.Template] = [
    Resource.Template(
        uriTemplate: "coderpad://account/{account}/pad/{id}",
        name: "Account pad",
        description: "A single pad's full detail as JSON for the selected account.",
        mimeType: "application/json"
    ),
    Resource.Template(
        uriTemplate: "coderpad://account/{account}/pad/{id}/code",
        name: "Account pad code",
        description: "Just the code in a pad for the selected account.",
        mimeType: "application/json"
    ),
    Resource.Template(
        uriTemplate: "coderpad://account/{account}/question/{id}",
        name: "Account question",
        description: "A single question's full detail as JSON for the selected account.",
        mimeType: "application/json"
    )
]

public func resourceTemplates(for accountSet: MCPAccountSet) -> [Resource.Template] {
    guard accountSet.accounts.count > 1 else { return resourceTemplates + accountResourceTemplates }

    return accountResourceTemplates
}

/// A parsed `coderpad://` resource request, decoupling URI shape from the fetch.
public enum ResourceRequest: Equatable {
    case quota
    case organization
    case pad(String)
    case padCode(String)
    case question(Int)
    case accountQuota(String)
    case accountOrganization(String)
    case accountPad(account: String, id: String)
    case accountPadCode(account: String, id: String)
    case accountQuestion(account: String, id: Int)

    public var accountName: String? {
        switch self {
        case let .accountQuota(account),
             let .accountOrganization(account),
             let .accountPad(account, _),
             let .accountPadCode(account, _),
             let .accountQuestion(account, _):
            account
        default:
            nil
        }
    }

    public var unqualified: Self {
        switch self {
        case .quota, .organization, .pad, .padCode, .question:
            self
        case .accountQuota:
            .quota
        case .accountOrganization:
            .organization
        case let .accountPad(_, id):
            .pad(id)
        case let .accountPadCode(_, id):
            .padCode(id)
        case let .accountQuestion(_, id):
            .question(id)
        }
    }
}

/// Parses a `coderpad://` URI into a request, or nil when it doesn't match any known
/// resource. Tolerates a trailing slash and percent-encoded ids.
public func parseResourceURI(_ uri: String) -> ResourceRequest? {
    guard let components = URLComponents(string: uri), components.scheme == resourceScheme else {
        return nil
    }

    // For coderpad://pad/x the host is "pad" and the path is "/x"; normalize both into
    // one list of segments so the matching below reads uniformly.
    var segments: [String] = []
    if let host = components.host, !host.isEmpty { segments.append(host) }
    segments += components.path.split(separator: "/").map(String.init)
    let decoded = segments.map { $0.removingPercentEncoding ?? $0 }

    return parseUnqualifiedResource(decoded) ?? parseAccountResource(decoded)
}

private func parseUnqualifiedResource(_ decoded: [String]) -> ResourceRequest? {
    switch decoded.first {
    case "quota" where decoded.count == 1:
        .quota
    case "organization" where decoded.count == 1:
        .organization
    case "pad":
        parsePadResource(Array(decoded.dropFirst()))
    case "question":
        parseQuestionResource(Array(decoded.dropFirst()))
    default:
        nil
    }
}

private func parseAccountResource(_ decoded: [String]) -> ResourceRequest? {
    guard decoded.count >= 3, decoded[0] == "account", !decoded[1].isEmpty else { return nil }

    let account = decoded[1]
    switch decoded[2] {
    case "quota" where decoded.count == 3:
        return .accountQuota(account)
    case "organization" where decoded.count == 3:
        return .accountOrganization(account)
    case "pad":
        return parseAccountPadResource(account: account, tail: Array(decoded.dropFirst(3)))
    case "question":
        return parseAccountQuestionResource(account: account, tail: Array(decoded.dropFirst(3)))
    default:
        return nil
    }
}

private func parsePadResource(_ tail: [String]) -> ResourceRequest? {
    switch tail.count {
    case 1 where !tail[0].isEmpty:
        .pad(tail[0])
    case 2 where !tail[0].isEmpty && tail[1] == "code":
        .padCode(tail[0])
    default:
        nil
    }
}

private func parseQuestionResource(_ tail: [String]) -> ResourceRequest? {
    guard tail.count == 1, let id = Int(tail[0]) else { return nil }

    return .question(id)
}

private func parseAccountPadResource(account: String, tail: [String]) -> ResourceRequest? {
    switch tail.count {
    case 1 where !tail[0].isEmpty:
        .accountPad(account: account, id: tail[0])
    case 2 where !tail[0].isEmpty && tail[1] == "code":
        .accountPadCode(account: account, id: tail[0])
    default:
        nil
    }
}

private func parseAccountQuestionResource(account: String, tail: [String]) -> ResourceRequest? {
    guard tail.count == 1, let id = Int(tail[0]) else { return nil }

    return .accountQuestion(account: account, id: id)
}

public enum ResourceAccountResolution: Equatable {
    case account(MCPAccount)
    case requiresAccount
    case unknownAccount(String)
}

public func resolveResourceAccount(_ request: ResourceRequest, accountSet: MCPAccountSet) -> ResourceAccountResolution {
    if let accountName = request.accountName {
        guard let account = accountSet.resolve(accountName) else { return .unknownAccount(accountName) }

        return .account(account)
    }

    guard accountSet.accounts.count == 1 else { return .requiresAccount }

    return .account(accountSet.defaultAccount)
}

private func resourcePathComponent(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
