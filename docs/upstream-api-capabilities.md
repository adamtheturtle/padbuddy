# Upstream API capability boundaries

[Issue #2887](https://github.com/adamtheturtle/padbuddy/issues/2887) remains the tracker for five upstream capabilities and their app follow-up.
Keep it open until all five are complete.
This inventory records the app's current fallbacks and the evidence needed to replace them.
It does not claim that mock fixtures prove live API support.

## Person identity and roles

The documented [current-user endpoint](https://developers.coderpad.io/reference/getuser) exists.
CoderPadKit 0.6.2 models its display name, `analytics_id`, and `allow_pad_creation`; PadBuddy presents these through `InterviewKeyOwnerView`.
That response does not establish the API key owner's email or organization role in the current SDK contract.
Continue to use the selected owner email for email-based filters until an authoritative identity is available.
An analytics identifier is not an email address.

Pad event actor email support is also distinct from stable participant identity and interviewer/candidate roles. Do not infer authoritative roles from display-name matches or assume that an event actor represents every participant in a pad. Verify a documented identity/role response, update SDK models and fixtures, and define the visible role-dependent behavior before replacing these fallbacks.

## Project and framework pad creation

The [create-pad reference](https://developers.coderpad.io/reference/createpad) documents creation, including initialization from a question.
The tracker's direct project/framework-slug failures remain separate from creating a question-backed pad or editing question variants.
Keep the web-creation option until representative direct framework creation succeeds through the documented API-key interface and has live-contract and mock coverage.
A project question or variant in a mock response does not prove that direct `POST /api/pads` accepts the same slug.

## Shared favorite questions

Local and iCloud favorites remain the fallback.
Replace them only after verifying a documented API-key read/write favorite contract and its synchronization semantics.
Preserve offline behavior and cover conflict, deletion, and multiple-device reconciliation when adding that integration.
The web Question Bank's star does not itself establish REST favorite support.

## Project question starter files

The app-side preparation is implemented:

- CoderPadKit models optional question project metadata and `file_contents`.
- `QuestionDetailView` renders supplied project files, including blank and deletion entries.
- An absent starter payload shows **Starter code unavailable**, explaining that template files may still exist in CoderPad.
- `QuestionProjectStarterFilesTests` covers supplied and absent files, both appearances, and rendering without single-file `contents`.
  `QuestionDecoderTests` covers the omitted REST project payload recorded in #2887.

The documented [question endpoint](https://developers.coderpad.io/reference/getquestion) is the recheck point.
The remaining upstream step is to confirm that API-key-authenticated retrieval actually returns the complete project starter files and template metadata for a known project question.
Retain the unavailable state when it does not.
A signed-in website/GraphQL response is not interchangeable with the API-key contract.

## Recorded playback output

The [pad-events endpoint](https://developers.coderpad.io/reference/listpadevents) exposes run events.
A run event is distinct from recorded stdout, stderr, or REPL output.
Keep the unavailable-output behavior until a documented API-key response supplies bounded output associated with the run and environment.
Then add SDK fixtures and playback coverage for success, runtime errors, empty output, and unavailable output.
Never re-execute historical code to reconstruct missing output.

## Recheck and close

Use the documented API-key endpoints and a known, consented fixture account.
Record sanitized field presence and behavior rather than API keys, participant details, or raw private project contents.
A capability is complete only when its live contract, SDK support, app behavior, and regression coverage are all present.
Update the independent checkboxes in #2887 as each capability arrives; partial app preparation can merge while the umbrella remains open.
