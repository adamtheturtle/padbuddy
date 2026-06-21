# CoderPad MCP server

A small, standalone [Model Context Protocol](https://modelcontextprotocol.io)
server that exposes a CoderPad account's pads and questions to MCP-aware tools
(Claude, editors, agents). It talks to the CoderPad REST API directly over stdio,
so it runs on its own without the macOS app (issue #393).

It lives in its own Swift package at the repo root — a sibling of the app and of
`PaginatedRESTClient` — and never touches the app target.

## Tools

All tools are **read-only** by design: a server an assistant can drive shouldn't
be able to create, edit, or delete interview content. Each returns the CoderPad
API's JSON verbatim.

| Tool | Arguments | Returns |
| --- | --- | --- |
| `list_pads` | `page` (int, optional), `sort` (string, optional) | A page of pads (≤50), with `next_page` / `total` |
| `get_pad` | `id` (string, required) | One pad's full detail |
| `get_pad_code` | `id` (string, required), `max_file_chars` (int, optional) | Just the pad's code — each file's `filename`, `language`, and `contents` (single-file and multi-file) |
| `count_pads` | `owner` / `state` / `language` (string, optional) | Just the matched total — pages the whole list internally, no records returned |
| `aggregate_pads` | `group_by` (string, required: owner/language/state/month), `owner` / `state` / `language` (optional) | Counts grouped by a field, computed in-process — e.g. pads per owner over a large org |
| `list_pads_compact` | `page` (int, optional), `sort` (string, optional) | One page of pads with only id, title, owner_email, state, language, created_at (far smaller than `list_pads`) |
| `list_questions` | `page` (int, optional), `sort` (string, optional) | A page of questions (≤50), with `next_page` / `total` |
| `get_question` | `id` (int, required) | One question's full detail |
| `get_quota` | — | The account's pad-quota usage |
| `get_organization` | — | The org directory (teams + members) |

### CoderPad Screen (assessments)

These are offered **only when a Screen key is configured** (see below), since
Screen is a separate product with its own API key and host (#314):

| Tool | Arguments | Returns |
| --- | --- | --- |
| `screen_list_campaigns` | — | The org's assessment campaigns |
| `screen_list_tests` | `campaignId` (int), `candidateEmail` (string), `start` (int), `limit` (int) — all optional | A page of test sessions (offset pagination via `pagination.nextStart`) |
| `screen_get_test` | `id` (int, required) | One test session's status and report |

### Write tools (create / edit)

**Off by default.** These are advertised and usable only when
`CODERPAD_MCP_ALLOW_WRITES` is set (see below) — enabling the server alone does not
grant write access (#502). They're marked non-read-only (and updates destructive) so
MCP clients can prompt before running them. There is **no delete tool** by design:
deletion stays a human action in the app.

| Tool | Arguments | Does |
| --- | --- | --- |
| `create_pad` | `title` / `language` / `owner_email` / `contents` / `notes` / `team_id` (string), `question_id` (int) — all optional | Creates a pad (seed with `contents` OR `question_id`) |
| `update_pad` | `id` (string, required); `title` / `notes` / `owner_email` / `language` (optional) | Updates a pad's fields |
| `create_question` | `title` (string, required); `language` / `description` / `solution` / `contents` (optional) | Creates a question |
| `update_question` | `id` (int, required); `title` / `language` / `description` / `solution` / `contents` (optional) | Updates a question |

## Prompts

The server also offers a few reusable **prompts** (issue #517) — argument-driven
instructions an MCP client can surface as slash-commands or quick actions, so the
assistant knows how to drive the tools for a common task without being told from
scratch each time:

| Prompt | Arguments | Does |
| --- | --- | --- |
| `review_pad_code` | `pad_id` (required) | Reviews a pad's code for correctness, complexity, and clarity |
| `summarize_pad` | `pad_id` (required) | Summarizes an interview pad's problem, approach, and outcome |
| `compare_pads` | `pad_ids` (required, comma-separated) | Compares several pads to help rank candidates |
| `draft_question` | `topic` (required), `language` / `difficulty` (optional) | Drafts a new interview question |

## Resources

Pads, questions, and the account singletons are also exposed as MCP **resources**
(issue #517), addressable by a `coderpad://` URI. The quota and organization
resources are listed directly; pads and questions are URI templates the client
fills in. Each resolves to the same JSON the corresponding tool returns.

| URI | Resource |
| --- | --- |
| `coderpad://quota` | The account's pad-quota usage |
| `coderpad://organization` | The org directory (teams + members) |
| `coderpad://pad/{id}` | One pad's full detail |
| `coderpad://pad/{id}/code` | Just the pad's code (each file) |
| `coderpad://question/{id}` | One question's full detail |

## Configuration

Set via the environment:

| Variable | Required | Default | Notes |
| --- | --- | --- | --- |
| `CODERPAD_API_KEY` | yes | — | A CoderPad API key (Settings → API on coderpad.io) |
| `CODERPAD_BASE_URL` | no | `https://app.coderpad.io` | Override for self-hosted / regional deployments |
| `CODERPAD_SCREEN_API_KEY` | no | — | A CoderPad Screen API key. When set, the `screen_*` tools are enabled |
| `CODERPAD_SCREEN_REGION` | no | US | Set to `eu` for EU-hosted Screen organizations |
| `CODERPAD_MCP_ALLOW_WRITES` | no | off | Set to `1`/`true`/`yes`/`on` to enable the create/edit (write) tools. Off by default |

## Build & run

```sh
cd CoderPadMCP
swift build -c release
CODERPAD_API_KEY=your-key swift run coderpad-mcp
```

The release binary is at `.build/release/coderpad-mcp`.

## Wiring it into an MCP client

Point your MCP client at the built binary. For example, in a Claude
`mcpServers` config:

```json
{
  "mcpServers": {
    "coderpad": {
      "command": "/absolute/path/to/coderpad-macos/CoderPadMCP/.build/release/coderpad-mcp",
      "env": { "CODERPAD_API_KEY": "your-key" }
    }
  }
}
```
