# PadBuddy roadmap

GitHub Issues is the authoritative roadmap:
<https://github.com/adamtheturtle/coderpad-macos/issues>.

This file intentionally does not duplicate individual checkboxes. The previous
hand-maintained list drifted far behind the project and continued to describe
shipping capabilities—multi-platform targets, sandboxing, privacy manifests,
Sparkle releases, hardened runtime, listing metadata, and screenshots—as
unfinished work.

## Current priorities

Use issue labels and milestones to plan work:

- bugs and security/release-integrity issues first;
- accessibility and platform-polish issues that need visual verification next;
- performance work only with a repeatable benchmark;
- external blockers remain open with their blocking label.

Useful maintainer queries:

```sh
gh issue list --state open --label bug
gh issue list --state open --label needs-visual-check
gh issue list --state open --label needs-performance-verification
gh issue list --state open --label blocked-on-apple-developer-account
```

## Current product facts

- Product name: PadBuddy / Pads for CoderPad.
- Bundle identifier: `com.adamdangoor.padbuddy`.
- Supported app destinations are defined by the checked-in Xcode project and
  include Apple platforms beyond macOS.
- Direct releases use Sparkle and `v*` tags; App Store validation uses the
  Sparkle-free `CoderPad-AppStore` target and `appstore-v*` tags.
- Privacy manifests, App Store metadata, release notes, screenshots, and
  distribution documentation live in their dedicated checked-in files.

When a durable product fact changes, update its authoritative project,
workflow, or documentation file. Track actionable work as an issue rather than
adding another checkbox here.
