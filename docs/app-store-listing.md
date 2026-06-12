# App Store listing & review content

Ready-to-paste copy for App Store Connect. Character limits are noted and
respected. All copy reflects the app as it actually behaves.

> **Trademark / affiliation note:** "CoderPad" is a trademark of CoderPad, Inc.
> This is an unofficial third-party client. Apple's guidelines generally expect
> a third-party app to use a "<name> for <Service>" form rather than the bare
> trademark, and to make non-affiliation clear. The recommended name below
> follows that convention — adjust if you have permission to use the mark
> directly.

## App name — #55 (≤30)
**Pads for CoderPad** _(17 chars)_

Alternatives if you prefer: "PadPilot for CoderPad" (21), "Pad Companion for CoderPad" (26).

## Subtitle — #56 (≤30)
**Manage your interview pads** _(26 chars)_

## Promotional text — #57 (≤170)
**A fast, native macOS client for browsing, searching, and managing your CoderPad pads and questions, with a built-in pad browser and quick menu bar access.** _(155 chars)_

## Keywords — #59 (≤100, comma separated)
`coderpad,interview,pads,coding,developer,questions,technical,hiring,recruiter,client,interviews` _(95 chars)_

## Primary / secondary category — #64
- **Primary:** Developer Tools
- **Secondary:** Productivity

## Age rating — #65
**4+** — no objectionable content.

## Support URL — #60
<https://github.com/adamtheturtle/coderpad-macos/issues>

## Marketing URL — #61 (optional)
<https://github.com/adamtheturtle/coderpad-macos>

## Privacy policy URL — #46
Host `docs/privacy-policy.md` (e.g. via GitHub Pages) and use that URL. Until
Pages is enabled, the rendered source works:
<https://github.com/adamtheturtle/coderpad-macos/blob/main/docs/privacy-policy.md>

## Localizations — #67
**en-US** at launch. Additional languages can be added later (tracked separately in #111).

## Description — #58 (≤4000)

> Pads for CoderPad is a fast, native macOS client for your CoderPad account. Browse, search, and manage your interview pads and questions from the menu bar or a full window, without opening a browser tab.
>
> Pads for CoderPad is an unofficial, third-party app. It requires an existing CoderPad account and your own CoderPad API key. It is free to download.
>
> FEATURES
>
> • Pads, at a glance — Browse every pad with fast search and filters for state, language, owner, team, type, and date. Your pads stay cached so the app opens instantly.
> • Pad detail — Read the code with syntax highlighting (single- and multi-file), step through the session event timeline, and see the whiteboard, notes, and participants.
> • Create and manage — Start a new pad, seed it from a question, edit details, end an interview, or delete a pad — all from the app.
> • Questions — Browse and search your question bank, star your favorites for one-click new pads, and create or edit questions.
> • Organization & quota — See your organization's members and pad-usage stats, and keep an eye on your plan's pad quota.
> • Built-in pad browser — Open a pad in an in-app browser window instead of leaving the app.
> • Menu bar quick access — Create a new pad, jump to your recent pads, or start one from a favorite question straight from the menu bar.
> • Multiple accounts — Switch between CoderPad accounts, including self-hosted or regional deployments.
> • Saved searches — Name and recall your most useful filter combinations.
> • Light and dark — A clean Mac-native interface that follows your appearance.
>
> PRIVACY
>
> Your API key is stored only in the local macOS Keychain and is used solely to talk to CoderPad's own API. The app collects no analytics, shows no ads, and has no developer-operated server. See the privacy policy for details.
>
> Not affiliated with, or endorsed by, CoderPad, Inc.

## App Review notes — #69 reviewer instructions + #68 demo access

> Pads for CoderPad is a thin, unofficial client over CoderPad's public REST API
> (https://app.coderpad.io). The user supplies their own CoderPad API key; the
> app stores it only in the local macOS Keychain and uses it only to call
> CoderPad's API on the user's behalf. There is no developer-operated backend,
> no account sign-up, and no data collection.
>
> SEEING DATA DURING REVIEW
>
> The app needs a valid CoderPad API key to show real content; without one it
> correctly shows an empty / "add an account" state. To review the full
> functionality, please add an account in Settings and paste this read-only
> review key:
>
>     API key: <PASTE A REAL READ-ONLY CODERPAD API KEY HERE BEFORE SUBMITTING>
>     Server URL: leave blank (uses https://app.coderpad.io)
>     Your Email: pick the matching member after the key validates
>
> (The in-app "Mock data" demo account is compiled into Debug builds only and is
> not present in this Release build, so a real review key is the reliable way to
> exercise the app.)

> **Action required before submitting:** generate a CoderPad API key on an
> account that has a few sample pads/questions and paste it into the review note
> above. A dedicated, low-privilege account is ideal.
