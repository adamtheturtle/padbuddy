//
//  ToolCatalog.swift
//  CoderPadToolCore
//
//  The single source of truth for the CoderPad MCP tool catalog (#521): tool names,
//  descriptions, input schemas, gating, and write annotations, expressed as plumbing-
//  neutral JSON ([String: Any]) so both servers build their own tool objects from it.
//  The in-app `--mcp` server (BuddyMCP / hand-rolled JSON-RPC) returns these descriptors
//  almost verbatim; the standalone `coderpad-mcp` CLI converts each to an `MCP.Tool`.
//  Defining a tool here means it appears, identically, on both servers.
//
//  Every account-scoped tool carries an optional `account` argument (the servers can act
//  as several accounts) resolved by name against list_accounts.
//

import Foundation

// MARK: - Schema builders

/// A tool descriptor: `{ name, description, inputSchema: { type, properties, required? },
/// annotations? }` — the shape both servers expect.
public func mcpToolDescriptor(
    _ name: String,
    _ description: String,
    properties: [String: [String: Any]] = [:],
    required: [String] = [],
    annotations: [String: Any] = [:]
) -> [String: Any] {
    var schema: [String: Any] = ["type": "object", "properties": properties]
    if !required.isEmpty { schema["required"] = required }
    var descriptor: [String: Any] = ["name": name, "description": description, "inputSchema": schema]
    if !annotations.isEmpty { descriptor["annotations"] = annotations }
    return descriptor
}

public func mcpStringSchema(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
}

public func mcpIntSchema(_ description: String) -> [String: Any] {
    ["type": "integer", "description": description]
}

/// The name of the optional account-selector argument shared by every account-scoped tool.
public let mcpAccountArgument = "account"

/// Schema for the `account` argument: which configured account to target.
public var mcpAccountSchema: [String: Any] {
    mcpStringSchema(
        "Optional. Which account to use, by its name (see list_accounts). Defaults to the default account."
    )
}

/// Description for a created_at date-range bound argument, shared by the pad and question
/// filter schemas.
public func mcpDateBoundDescription(bound: String) -> String {
    "Only records created \(bound) this date. Accepts a month (\"2026-03\"), a date "
        + "(\"2026-03-01\"), or a full ISO8601 timestamp; inclusive at the given granularity."
}

/// Adds the `account` selector to a property set.
private func withAccount(_ properties: [String: [String: Any]] = [:]) -> [String: [String: Any]] {
    properties.merging([mcpAccountArgument: mcpAccountSchema]) { _, new in new }
}

private var padFilterProperties: [String: [String: Any]] {
    [
        "owner": mcpStringSchema("Only pads whose owner_email matches this, case-insensitively."),
        "state": mcpStringSchema("Only pads in this state (e.g. \"active\", \"ended\")."),
        "language": mcpStringSchema("Only pads in this language (e.g. \"python\")."),
        "created_after": mcpStringSchema(mcpDateBoundDescription(bound: "on or after")),
        "created_before": mcpStringSchema(mcpDateBoundDescription(bound: "on or before"))
    ]
}

private var questionFilterProperties: [String: [String: Any]] {
    [
        "owner": mcpStringSchema("Only questions whose owner_email matches this, case-insensitively."),
        "author": mcpStringSchema("Only questions whose author_name matches this, case-insensitively."),
        "language": mcpStringSchema("Only questions in this language (e.g. \"python\")."),
        "type": mcpStringSchema("Only questions of this pad_type (e.g. \"sandbox\", \"take_home\")."),
        "created_after": mcpStringSchema(mcpDateBoundDescription(bound: "on or after")),
        "created_before": mcpStringSchema(mcpDateBoundDescription(bound: "on or before"))
    ]
}

private var pagingProperties: [String: [String: Any]] {
    [
        "page": mcpIntSchema("1-based page number."),
        "sort": mcpStringSchema("Sort order, e.g. \"created_at\" or \"-created_at\".")
    ]
}

/// Standard MCP annotations for a write tool: not read-only; touches an external system
/// (open-world); `destructiveHint` set for edits that overwrite existing content so
/// clients can warn more strongly than for a plain create.
private func writeAnnotations(title: String, destructive: Bool) -> [String: Any] {
    ["title": title, "readOnlyHint": false, "destructiveHint": destructive, "openWorldHint": true]
}

// MARK: - Catalog

/// The always-available read tools.
public var coderPadReadToolDescriptors: [[String: Any]] {
    [
        mcpToolDescriptor(
            "list_accounts",
            "List the CoderPad accounts this server can act as (name, base URL, and which is the default). "
                + "No API keys are returned. Use a name with the `account` argument on any other tool to "
                + "target a specific account."
        ),
        mcpToolDescriptor(
            "whoami",
            "Report which CoderPad account this server is acting as: the account name, the organization "
                + "name, and the server base URL. Never returns the API key. Use this to confirm identity "
                + "before answering organization-wide questions.",
            properties: withAccount()
        ),
        mcpToolDescriptor(
            "list_pads",
            "List the account's pads (most recent first). Optional page and sort.",
            properties: withAccount(pagingProperties)
        ),
        mcpToolDescriptor(
            "get_pad",
            "Get a single pad by its slug/id.",
            properties: withAccount(["pad": mcpStringSchema("The pad's slug or id.")]),
            required: ["pad"]
        ),
        mcpToolDescriptor(
            "get_pad_code",
            "Return just the code in a pad: each file with its filename, language, and contents (handles "
                + "both legacy single-file pads and multi-file environments). Use this to read a candidate's "
                + "code without the whole pad object.",
            properties: withAccount([
                "pad": mcpStringSchema("The pad's slug or id."),
                "max_file_chars": mcpIntSchema("Optional. Truncate each file to this many characters.")
            ]),
            required: ["pad"]
        ),
        mcpToolDescriptor(
            "count_pads",
            "Count pads, optionally filtered, WITHOUT returning the records — one cheap call instead of "
                + "paging every verbose record through the model.",
            properties: withAccount(padFilterProperties)
        ),
        mcpToolDescriptor(
            "aggregate_pads",
            "Group pads by a field and return only the counts (not the records) — e.g. how many pads each "
                + "owner has, over a large org, without blowing the assistant's context.",
            properties: withAccount(padFilterProperties.merging([
                "group_by": mcpStringSchema("Field to group by: owner, language, state, or month.")
            ]) { _, new in new }),
            required: ["group_by"]
        ),
        mcpToolDescriptor(
            "list_pads_compact",
            "Like list_pads but returns only id, title, owner_email, state, language, and created_at per "
                + "pad, so far more rows fit per response.",
            properties: withAccount(pagingProperties)
        ),
        mcpToolDescriptor(
            "list_questions",
            "List the account's question bank. Optional page and sort.",
            properties: withAccount(pagingProperties)
        ),
        mcpToolDescriptor(
            "get_question",
            "Get a single question by its numeric id.",
            properties: withAccount(["question": mcpIntSchema("The question's numeric id.")]),
            required: ["question"]
        ),
        mcpToolDescriptor(
            "count_questions",
            "Count questions in the bank, optionally filtered, WITHOUT returning the records — one cheap "
                + "call instead of paging every verbose record through the model.",
            properties: withAccount(questionFilterProperties)
        ),
        mcpToolDescriptor(
            "aggregate_questions",
            "Group questions by a field and return only the counts (not the records) — e.g. how many "
                + "questions per language or author, over a large bank, without blowing the assistant's "
                + "context.",
            properties: withAccount(questionFilterProperties.merging([
                "group_by": mcpStringSchema("Field to group by: owner, author, language, type, or month.")
            ]) { _, new in new }),
            required: ["group_by"]
        ),
        mcpToolDescriptor(
            "list_questions_compact",
            "Like list_questions but returns only id, title, owner_email, author_name, language, pad_type, "
                + "is_draft, and created_at per question, so far more rows fit per response.",
            properties: withAccount(pagingProperties)
        ),
        mcpToolDescriptor(
            "get_quota",
            "Get the organization's pad usage quota.",
            properties: withAccount()
        ),
        mcpToolDescriptor(
            "get_organization",
            "Get the organization's teams and members.",
            properties: withAccount()
        )
    ]
}

/// CoderPad Screen (assessments) tools, offered only when a Screen key is set.
public var coderPadScreenToolDescriptors: [[String: Any]] {
    [
        mcpToolDescriptor(
            "screen_list_campaigns",
            "List the account's CoderPad Screen assessment campaigns. Screen is the automated-assessment "
                + "product, separate from the interview pads.",
            properties: withAccount()
        ),
        mcpToolDescriptor(
            "screen_list_tests",
            "List Screen test sessions (candidate assessments), optionally filtered by campaign or "
                + "candidate email. Offset-paginated via start/limit.",
            properties: withAccount([
                "campaignId": mcpIntSchema("Optional. Only sessions in this campaign."),
                "candidateEmail": mcpStringSchema("Optional. Only sessions for this candidate email."),
                "start": mcpIntSchema("Optional. Offset of the first session to return."),
                "limit": mcpIntSchema("Optional. Maximum number of sessions to return.")
            ])
        ),
        mcpToolDescriptor(
            "screen_get_test",
            "Get a single Screen test session by its numeric id, including its report.",
            properties: withAccount(["test": mcpIntSchema("The session's numeric id.")]),
            required: ["test"]
        )
    ]
}

/// Write tools (create/edit), advertised only when writes are opted in. There is no
/// delete tool by design (#502): deletion stays a human action in the app.
public var coderPadWriteToolDescriptors: [[String: Any]] {
    [
        mcpToolDescriptor(
            "create_pad",
            "Create a new pad (optionally seeded from a question or starting code). Returns the new pad, "
                + "including its slug/id and URL.",
            properties: withAccount([
                "title": mcpStringSchema("Optional pad title."),
                "language": mcpStringSchema("Optional language, e.g. \"python3\"."),
                "question_id": mcpIntSchema("Optional question id to seed the pad from. Mutually exclusive with contents."),
                "contents": mcpStringSchema("Optional starting code. Mutually exclusive with question_id."),
                "owner_email": mcpStringSchema("Optional owner email; defaults to the account's user."),
                "notes": mcpStringSchema("Optional private interviewer notes."),
                "team_id": mcpStringSchema("Optional team id to link the pad to (org owners only).")
            ]),
            annotations: writeAnnotations(title: "Create pad", destructive: false)
        ),
        mcpToolDescriptor(
            "update_pad",
            "Edit a pad's title, notes, owner, or language. Does not change or reset the pad's code, and "
                + "cannot delete it.",
            properties: withAccount([
                "pad": mcpStringSchema("The pad's slug or id."),
                "title": mcpStringSchema("New title."),
                "notes": mcpStringSchema("New private interviewer notes."),
                "owner_email": mcpStringSchema("New owner email."),
                "language": mcpStringSchema("New language, e.g. \"python3\".")
            ]),
            required: ["pad"],
            annotations: writeAnnotations(title: "Update pad", destructive: true)
        ),
        mcpToolDescriptor(
            "create_question",
            "Create a question in the account's question bank. Returns the new question.",
            properties: withAccount([
                "title": mcpStringSchema("The question title (required)."),
                "language": mcpStringSchema("Optional language, e.g. \"python3\"."),
                "description": mcpStringSchema("Optional Markdown prompt shown to the interviewer."),
                "solution": mcpStringSchema("Optional reference solution."),
                "contents": mcpStringSchema("Optional starter code inserted into the session.")
            ]),
            required: ["title"],
            annotations: writeAnnotations(title: "Create question", destructive: false)
        ),
        mcpToolDescriptor(
            "update_question",
            "Edit an existing question's title, language, description, solution, or starter code. Cannot "
                + "delete the question.",
            properties: withAccount([
                "question": mcpIntSchema("The question's numeric id."),
                "title": mcpStringSchema("New title."),
                "language": mcpStringSchema("New language, e.g. \"python3\"."),
                "description": mcpStringSchema("New Markdown prompt."),
                "solution": mcpStringSchema("New reference solution."),
                "contents": mcpStringSchema("New starter code.")
            ]),
            required: ["question"],
            annotations: writeAnnotations(title: "Update question", destructive: true)
        )
    ]
}

/// The names of the write tools, gated on the writes opt-in. One set so the `tools/list`
/// filter and the call gate can't drift apart.
public let coderPadWriteToolNames: Set<String> = [
    "create_pad", "update_pad", "create_question", "update_question"
]

/// The names of the Screen tools, advertised only when Screen is configured.
public let coderPadScreenToolNames: Set<String> = [
    "screen_list_campaigns", "screen_list_tests", "screen_get_test"
]

/// The full catalog to advertise: Screen tools appear only when Screen is configured, and
/// write tools only when writes are opted in — so a client is never offered a tool it
/// can't use.
public func coderPadToolDescriptors(screenEnabled: Bool, writesEnabled: Bool) -> [[String: Any]] {
    var result = coderPadReadToolDescriptors
    if screenEnabled { result += coderPadScreenToolDescriptors }
    if writesEnabled { result += coderPadWriteToolDescriptors }
    return result
}
