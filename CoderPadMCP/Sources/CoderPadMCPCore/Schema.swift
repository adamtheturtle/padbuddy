//
//  Schema.swift
//  CoderPadMCPCore
//
//  The tool catalog: input schemas plus which tools to advertise. The read tools are
//  always available; the Screen tools appear only when a Screen key is configured
//  (#314); the write tools only when writes are opted in (#502).
//

import MCP

public func property(_ type: String, _ description: String) -> Value {
    .object(["type": .string(type), "description": .string(description)])
}

public func objectSchema(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
    var schema: [String: Value] = ["type": .string("object"), "properties": .object(properties)]
    if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
    return .object(schema)
}

public let pagingProperties: [String: Value] = [
    "page": property(
        "integer",
        "1-based page number. The API returns up to 50 items per page; the response includes \"next_page\" when more remain."
    ),
    "sort": property("string", "Optional sort field accepted by the CoderPad API (e.g. \"created_at\").")
]

/// Client-side filters shared by the pad count/aggregate tools. Filtering happens
/// in-process while paging the list, since the CoderPad list API has no server-side
/// filter parameters.
public let padFilterProperties: [String: Value] = [
    "owner": property("string", "Only pads whose owner_email matches this, case-insensitively."),
    "state": property("string", "Only pads in this state (e.g. \"active\", \"ended\")."),
    "language": property("string", "Only pads in this language (e.g. \"python\").")
]

/// The always-available read tools.
public let readTools: [Tool] = [
    Tool(
        name: "whoami",
        description: "Report which CoderPad account this server is acting as: the organization name, the server base URL, and whether Screen and write tools are enabled. Never returns the API key. Use this to confirm identity before answering organization-wide questions.",
        inputSchema: objectSchema()
    ),
    Tool(
        name: "list_pads",
        description: "List the organization's pads (interview sessions), paginated. Returns the raw CoderPad API JSON, including next_page and total.",
        inputSchema: objectSchema(pagingProperties)
    ),
    Tool(
        name: "get_pad",
        description: "Fetch a single pad by its id (slug), with its full detail.",
        inputSchema: objectSchema(["id": property("string", "The pad id / slug.")], required: ["id"])
    ),
    Tool(
        name: "get_pad_code",
        description: "Return just the code for a pad: every file with its filename, language, and contents. Handles both legacy single-file pads (the pad's \"contents\") and multi-file environments (each pad_environment's \"file_contents\"). Use this to read or review a candidate's code without digging through the whole pad object.",
        inputSchema: objectSchema([
            "id": property("string", "The pad id / slug."),
            "max_file_chars": property(
                "integer",
                "Optional. Truncate each file's contents to at most this many characters (full file contents can be large). Omit for the complete contents."
            )
        ], required: ["id"])
    ),
    Tool(
        name: "count_pads",
        description: "Count pads, optionally filtered, WITHOUT returning the records. Pages the whole list internally and returns just the matched total — so \"how many pads match X\" is one cheap call instead of pulling every page of verbose JSON through the model.",
        inputSchema: objectSchema(padFilterProperties)
    ),
    Tool(
        name: "aggregate_pads",
        description: "Group pads by a field and return only the counts (not the records). Pages the whole list internally and tallies in this process. Use this for questions like \"how many pads does each owner have?\" over large orgs without blowing the assistant's context.",
        inputSchema: objectSchema(
            padFilterProperties.merging([
                "group_by": property(
                    "string",
                    "Field to group by: \"owner\" (owner_email), \"language\", \"state\", or \"month\" (created_at year-month)."
                )
            ]) { _, new in new },
            required: ["group_by"]
        )
    ),
    Tool(
        name: "list_pads_compact",
        description: "Like list_pads but returns only id, title, owner_email, state, language, and created_at per pad (dropping the verbose blob), so far more rows fit per response. Includes next_page and total for driving pagination.",
        inputSchema: objectSchema(pagingProperties)
    ),
    Tool(
        name: "list_questions",
        description: "List the organization's question bank, paginated. Returns the raw CoderPad API JSON, including next_page and total.",
        inputSchema: objectSchema(pagingProperties)
    ),
    Tool(
        name: "get_question",
        description: "Fetch a single question by its numeric id, with its full detail.",
        inputSchema: objectSchema(["id": property("integer", "The numeric question id.")], required: ["id"])
    ),
    Tool(
        name: "get_quota",
        description: "Fetch the account's pad quota usage.",
        inputSchema: objectSchema()
    ),
    Tool(
        name: "get_organization",
        description: "Fetch the organization directory (teams and members).",
        inputSchema: objectSchema()
    )
]

/// CoderPad Screen (assessments) tools, offered only when a Screen key is set.
public let screenTools: [Tool] = [
    Tool(
        name: "screen_list_campaigns",
        description: "List the organization's CoderPad Screen assessment campaigns.",
        inputSchema: objectSchema()
    ),
    Tool(
        name: "screen_list_tests",
        description: "List CoderPad Screen test sessions (offset-paginated). The response's pagination.nextStart / hasMoreItems drive paging.",
        inputSchema: objectSchema([
            "campaignId": property("integer", "Only tests in this campaign."),
            "candidateEmail": property("string", "Only tests for this candidate email."),
            "start": property("integer", "Offset to start from (use pagination.nextStart from a prior call)."),
            "limit": property("integer", "Maximum number of tests to return.")
        ])
    ),
    Tool(
        name: "screen_get_test",
        description: "Fetch one CoderPad Screen test session (status and, once finished, its report) by numeric id.",
        inputSchema: objectSchema(["id": property("integer", "The numeric test-session id.")], required: ["id"])
    )
]

/// Annotations for write tools so MCP clients can warn before running them: not
/// read-only, and touching an external system. Updates also set `destructiveHint`
/// since they overwrite existing interview content.
public let createAnnotations = Tool.Annotations(readOnlyHint: false, destructiveHint: false, openWorldHint: true)
public let updateAnnotations = Tool.Annotations(readOnlyHint: false, destructiveHint: true, openWorldHint: true)

/// Write tools (create/edit), advertised only when writes are opted in. There is no
/// delete tool by design (#502): deletion stays a human action in the app.
public let writeTools: [Tool] = [
    Tool(
        name: "create_pad",
        description: "WRITE: create a new pad. All fields optional; seed code with `contents` OR a `question_id` (mutually exclusive). Returns the created pad, including its URL/slug.",
        inputSchema: objectSchema([
            "title": property("string", "Optional pad title."),
            "language": property("string", "Optional starting language (e.g. \"python\")."),
            "owner_email": property("string", "Optional owner email; defaults to the API key's user."),
            "contents": property("string", "Optional starting code. Mutually exclusive with question_id."),
            "notes": property("string", "Optional private interviewer notes."),
            "question_id": property("integer", "Optional question id to seed the pad from. Mutually exclusive with contents."),
            "team_id": property("string", "Optional team id (org owners only).")
        ]),
        annotations: createAnnotations
    ),
    Tool(
        name: "update_pad",
        description: "WRITE: update an existing pad's title, notes, owner, or language. Identify the pad by its id/slug.",
        inputSchema: objectSchema([
            "id": property("string", "The pad id / slug to update."),
            "title": property("string", "New title."),
            "notes": property("string", "New private interviewer notes."),
            "owner_email": property("string", "New owner email."),
            "language": property("string", "New language.")
        ], required: ["id"]),
        annotations: updateAnnotations
    ),
    Tool(
        name: "create_question",
        description: "WRITE: create a new question in the bank. `title` is required; the rest are optional. Returns the created question.",
        inputSchema: objectSchema([
            "title": property("string", "Question title (required)."),
            "language": property("string", "Optional language."),
            "description": property("string", "Optional description (Markdown)."),
            "solution": property("string", "Optional reference solution."),
            "contents": property("string", "Optional starter code.")
        ], required: ["title"]),
        annotations: createAnnotations
    ),
    Tool(
        name: "update_question",
        description: "WRITE: update an existing question's title, language, description, solution, or starter code. Identify it by its numeric id.",
        inputSchema: objectSchema([
            "id": property("integer", "The numeric question id to update."),
            "title": property("string", "New title."),
            "language": property("string", "New language."),
            "description": property("string", "New description (Markdown)."),
            "solution": property("string", "New reference solution."),
            "contents": property("string", "New starter code.")
        ], required: ["id"]),
        annotations: updateAnnotations
    )
]

/// The tools to advertise: the Screen ones appear only when Screen is configured,
/// and the write ones only when writes are opted in — so a client is never offered
/// tools it can't use.
public func availableTools(screenEnabled: Bool, writesEnabled: Bool) -> [Tool] {
    var result = readTools
    if screenEnabled { result += screenTools }
    if writesEnabled { result += writeTools }
    return result
}
