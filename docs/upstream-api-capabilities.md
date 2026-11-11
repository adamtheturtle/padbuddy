# Upstream API capability boundaries

[Issue #2887](https://github.com/adamtheturtle/padbuddy/issues/2887) tracks remaining API gaps and app follow-up.
Keep it open until the remaining capabilities and their integration are complete.
This inventory distinguishes documented contracts, released SDK support, app integration, and live verification.
Mock fixtures and HTTP 401 authentication failures do not establish a live contract's availability.

## Person identity and roles

The documented [current-user endpoint](https://developers.coderpad.io/reference/getuser) exists.
CoderPadKit models its display name, `analytics_id`, and `allow_pad_creation`; PadBuddy presents these through `InterviewKeyOwnerView`.
That response does not establish the Interview key owner's email or organization role.
Continue to use the selected owner email for email-based filters until an authoritative identity is available, because an analytics identifier does not establish an email address.

Interview analytics supply transcript speaker names and interviewer/candidate roles. Pad access controls list allowed interviewer emails. Neither establishes a stable directory of everyone who attended a pad or authored a question. The [artifact index](https://developers.coderpad.io/reference/getpadartifacts) offers a session artifact described as including participants. Investigate its actual identity and role fields, including owner-only access and ended-pad/submitted-take-home restrictions, before requesting duplicate upstream work.
Screen account introspection is a separate contract and does not establish Interview account identity.

Do not infer authoritative roles from display-name matches.
Verify the identity fields, update SDK models and fixtures, and define visible behavior before replacing participant name matching or the selected owner email.

## Project and framework pad creation

The [create-pad reference](https://developers.coderpad.io/reference/createpad) accepts project-template slugs such as `multifile_python` and `react` directly.
Structured `file_contents` overlays add, replace, or delete template files.
A ZIP replaces template files, retaining `.cpad` unless the archive supplies it.
A question seed excludes other content sources; project slugs exclude single-file `contents`.
Project responses have null `language` and `contents`; retrieve files through `pad_environment_ids` and the pad-environment endpoint.

[CoderPadKit 0.7.0](https://github.com/adamtheturtle/CoderPadKit/releases/tag/0.7.0) implements these requests and environment discovery.
[CoderPadMCP 0.5.0](https://github.com/adamtheturtle/CoderPadMCP/releases/tag/0.5.0) exposes discovery and project creation to agents.
[PadBuddy #5612](https://github.com/adamtheturtle/padbuddy/pull/5612) merged their adoption, native project/framework picker options, and removal of the web-only creation footer.
Merged app code and a published PadBuddy binary are separate milestones.
The historical slug rejection no longer describes the documented upstream boundary.

SDK transport tests and app request-normalization coverage pass.
Representative live project creation and returned-file verification remain outstanding: the available credentials returned HTTP 401, which establishes an authentication failure rather than an unsupported capability.
Live creation also requires authorization to write to the fixture account; the current CoderPad checks are read-only.

## Environment and starter-code discovery

CoderPadKit's `listLanguages()` and `getLanguage(_:)` read `/api/languages` and `/api/languages/{slug}` and preserve the catalogue JSON.
CoderPadMCP exposes `list_languages` and `get_language`.
These endpoints provide environment context without creating temporary pads, although their extensible response schema does not specify a complete typed file manifest.

PadBuddy's question viewer reads the relevant template slug with the question's account client.
The viewer recognizes a direct `file_contents` array with unique, non-empty paths, merges available defaults with returned overrides and additions, and retains deletion markers.
Blank, hidden, binary, and unavailable bodies remain distinct.
Unknown or malformed catalogue shapes and failed reads keep an explicit defaults-unavailable state; they must not be interpreted as empty templates.
Account and template changes invalidate earlier reads.

[Issue #5620](https://github.com/adamtheturtle/padbuddy/issues/5620) still requires an authoritative catalogue payload or schema to establish that the recognized shape supplies complete template defaults.
Current coverage uses synthetic payloads and does not establish the live response shape.
Do not promise complete starter-file viewing until that verification is recorded.

## Shared favorite questions

No API-key read/write favorite-question contract is established by the reviewed Interview reference or SDK.
Local and iCloud favorites remain the fallback.
Replace them after verifying a server contract and its synchronization semantics.
Preserve offline behavior and cover conflict, deletion, and multiple-device reconciliation.
The web Question Bank's star does not itself establish REST favorite support.

## Project question starter files

The documented [question](https://developers.coderpad.io/reference/getquestion) and [variant](https://developers.coderpad.io/reference/getquestionvariant) responses include starter-file customizations, hidden/deleted flags, and variant project-template metadata.
An empty project file list may represent an unmodified template.
A project variant may have null `language`; use its template slug and file extensions for presentation.

PadBuddy renders parent starter files and offers expandable variant previews independently of editing, including read-only mode.
Opening a variant preview fetches its details without creating a pad.
Missing bodies remain unavailable, blank text remains blank, and removed-template entries retain their removal marker.
Unchanged template files require the catalogue resolution described above.

CoderPadKit 0.7.1 introduced the optional `binary` marker in parent and variant responses.
PadBuddy adopts 0.7.2, which also preserves references to the original variant-file initializer.
The marker is response metadata and is excluded from variant mutation fields.
Binary bodies are absent from the documented response; no binary download contract is established.
PadBuddy labels binary files and explains that their text preview is unavailable.
Unrelated solution edits preserve existing variant code by omitting file fields.
Variant text/environment replacements are blocked when original file bodies are unavailable; parent text replacement is blocked for known binary files.
A complete project ZIP remains an explicit replacement path.
Resolved defaults are never written back as a side effect of viewing a question.

Live parent/variant reads still need verification for known project questions authored with structured files and ZIP uploads. Do not create temporary pads for ordinary question viewing or treat website/GraphQL responses as the API-key contract.

## Recorded playback output

The [pad-events endpoint](https://developers.coderpad.io/reference/listpadevents) exposes run events.
Interview analytics add spoken transcripts, highlights, outlines, and review reports.
The artifact index offers session/events, AI chats, environment files, and diffs. These do not establish a recorded stdout/stderr contract or run-to-output association.

Investigate whether artifacts supply that missing association before requesting an upstream extension.
Keep the unavailable-output behavior until an API-key response supplies bounded output associated with the run and environment.
Then add SDK fixtures and playback coverage for success, runtime errors, empty output, and unavailable output.
Never re-execute historical code to reconstruct missing output.

## Recheck and close

Use documented API-key endpoints and a known, consented fixture account.
Record sanitized field presence and behavior rather than API keys, participant details, or private project contents.
A capability is complete when its live contract, SDK support, app behavior, and regression coverage are present.
Update the independent checkboxes in #2887 as each capability arrives; downstream work can merge while the umbrella remains open.
