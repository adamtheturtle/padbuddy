//
//  Schema.swift
//  CoderPadMCPCore
//
//  Builds the standalone server's `MCP.Tool` list from the single shared catalog in
//  CoderPadToolCore (#521), so the CLI advertises exactly the same tools — names,
//  descriptions, schemas, gating, annotations — as the in-app server. The catalog is
//  plumbing-neutral JSON ([String: Any]); this file converts each descriptor into the
//  swift-sdk's `Tool`/`Value` types.
//

import CoderPadToolCore
import Foundation
import MCP

/// Converts a JSON value from the shared catalog into an MCP `Value`. Order matters:
/// Bool is checked before the numeric types so a flag isn't read as an int.
func mcpValue(_ any: Any) -> Value {
    switch any {
    case let value as Value: value
    case let bool as Bool: .bool(bool)
    case let int as Int: .int(int)
    case let double as Double: .double(double)
    case let string as String: .string(string)
    case let array as [Any]: .array(array.map(mcpValue))
    case let object as [String: Any]: .object(object.mapValues(mcpValue))
    default: .null
    }
}

/// Turns one shared descriptor (`{ name, description, inputSchema, annotations? }`) into
/// an `MCP.Tool`.
private func makeTool(_ descriptor: [String: Any]) -> Tool {
    let name = descriptor["name"] as? String ?? ""
    let description = descriptor["description"] as? String ?? ""
    let inputSchema = mcpValue(descriptor["inputSchema"] ?? [String: Any]())
    let annotations = (descriptor["annotations"] as? [String: Any]).map(makeAnnotations)
        ?? Tool.Annotations()
    return Tool(name: name, description: description, inputSchema: inputSchema, annotations: annotations)
}

private func makeAnnotations(_ dict: [String: Any]) -> Tool.Annotations {
    Tool.Annotations(
        title: dict["title"] as? String,
        readOnlyHint: dict["readOnlyHint"] as? Bool,
        destructiveHint: dict["destructiveHint"] as? Bool,
        openWorldHint: dict["openWorldHint"] as? Bool
    )
}

/// The tools to advertise, built from the shared catalog: Screen tools appear only when
/// Screen is configured, write tools only when writes are opted in.
public func availableTools(screenEnabled: Bool, writesEnabled: Bool) -> [Tool] {
    coderPadToolDescriptors(screenEnabled: screenEnabled, writesEnabled: writesEnabled).map(makeTool)
}
