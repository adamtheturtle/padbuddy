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

## Configuration

Set via the environment:

| Variable | Required | Default | Notes |
| --- | --- | --- | --- |
| `CODERPAD_API_KEY` | yes | — | A CoderPad API key (Settings → API on coderpad.io) |
| `CODERPAD_BASE_URL` | no | `https://app.coderpad.io` | Override for self-hosted / regional deployments |
| `CODERPAD_SCREEN_API_KEY` | no | — | A CoderPad Screen API key. When set, the `screen_*` tools are enabled |
| `CODERPAD_SCREEN_REGION` | no | US | Set to `eu` for EU-hosted Screen organizations |

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
