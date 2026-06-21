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

/// A parsed `coderpad://` resource request, decoupling URI shape from the fetch.
public enum ResourceRequest: Equatable {
    case quota
    case organization
    case pad(String)
    case padCode(String)
    case question(Int)
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

    switch decoded.count {
    case 1 where decoded[0] == "quota": return .quota

    case 1 where decoded[0] == "organization": return .organization

    case 2 where decoded[0] == "pad" && !decoded[1].isEmpty: return .pad(decoded[1])

    case 3 where decoded[0] == "pad" && decoded[2] == "code" && !decoded[1].isEmpty:
        return .padCode(decoded[1])

    case 2 where decoded[0] == "question":
        guard let id = Int(decoded[1]) else { return nil }

        return .question(id)

    default:
        return nil
    }
}
