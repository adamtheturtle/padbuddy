# Third-party library evaluation for the AppKit-bridge migrations

Tracking issue: #289.
Related: #284 (WebView), #285 (pull-to-refresh).

## Framing

The app drops to AppKit in two view bridges that have no shipping SwiftUI replacement: `PadBrowser` (`WKWebView` via `NSViewRepresentable`) and the pull-to-refresh `NSScrollView` bridge.
The question this evaluation answers is whether a third-party Swift package is worth adopting for either.

The decisive test, per the issue: a library that wraps `WKWebView` or `NSScrollView` **relocates** the `NSViewRepresentable` into a dependency.
It does not eliminate AppKit.
So adopting one never shrinks the structural "drops to AppKit" list; it can only be justified by deleting our own bridge boilerplate, and only when the dependency is well maintained and actually closes a capability gap we can't close ourselves.

## Candidates

| Library | Latest release | Swift / platforms | Maintained? | Closes a real gap? | Recommendation |
| --- | --- | --- | --- | --- | --- |
| [cybozu/WebUI](https://github.com/cybozu/WebUI) | 4.4.0 (Apr 2026) | Swift 6.2, Xcode 26.2; macOS 13.3+, iOS 16.4+, visionOS 2 | Yes, active (20 releases) | Partly | Hold. Track for #284, do not adopt now. |
| [dmytriigolovanov/webkit-user-agent](https://github.com/dmytriigolovanov/webkit-user-agent) | 4.0.0 (Nov 2022) | Swift 5.3; macOS 10.13+, iOS 11+ | No, stale ~3.5 yrs | No | Reject. |
| [elegantchaos/RefreshableScrollView](https://github.com/elegantchaos/RefreshableScrollView) | 1.3.1 (Nov 2022) | Unspecified; macOS support unclear | No, stale ~3.5 yrs | No | Reject. |
| [shakurocom/PullToRefreshSwiftUI](https://github.com/shakurocom/PullToRefreshSwiftUI) | 1.6.5 (Apr 2025) | Swift 5.9+; iOS 15 only, no macOS | Moderately active | No (iOS only) | Reject. |

## WebView (relates to #284)

### WebUI (cybozu) — strongest candidate

WebUI is the only candidate worth keeping on the radar.
It is actively maintained (4.4.0 in April 2026, built against Swift 6.2 / Xcode 26.2, macOS 13.3+), and it exposes exactly the two hooks that block the migration off our own bridge to SwiftUI's native `WebView`:

- **`window.open` OAuth popup.**
  WebUI's `.uiDelegate(_:)` modifier lets us attach a `WKUIDelegate`, so our `createWebViewWith` popup handler keeps working.
  Native SwiftUI `WebView` exposes no `WKUIDelegate`, which is why the native migration is blocked (see `WebKitForSwiftUI-not-yet` notes).
- **Safari user-agent suffix.**
  WebUI's `WebView(configuration:)` accepts a `WKWebViewConfiguration`, and the app sets its UA through `configuration.applicationNameForUserAgent` (`PadBrowser+Views.swift:23`, `PadBrowser.swift:161`), not a full `customUserAgent` override.
  So the suffix carries over unchanged.

**But it does not eliminate AppKit, and the win is small.**
WebUI is itself an `NSViewRepresentable` wrapping `WKWebView`; adopting it relocates that bridge into a dependency rather than removing it, so the structural AppKit count is unchanged.
And the genuinely AppKit-heavy part of `PadBrowser` is not the web view at all: it is the popup window management in the `WKUIDelegate` (`PadBrowser.swift:144-198`), which builds and tracks real `NSWindow`s for the sign-in popup and closes them on `webViewDidClose`.
That code stays exactly as it is whether the host is our `NSViewRepresentable` or WebUI's, because WebUI only hands us the delegate seat.
So adoption would let us delete the thin `makeNSView`/`updateNSView` host in `PadBrowser+Views.swift` and trade it for a dependency, while keeping all the `NSWindow` logic.

**Recommendation: hold.**
Do not adopt now.
The cost (a new dependency that still bridges to AppKit, plus longevity risk on a single-vendor package) is not repaid by deleting a small, stable host bridge we understand fully.
Revisit only if (a) our `WKWebView` host starts costing real maintenance, or (b) Apple's native `WebView` gains `WKUIDelegate` access, at which point we skip WebUI and go straight to the native API.
Re-check WebUI's maintenance at that time.

### WebKitUserAgent (dmytriigolovanov) — reject

Stale (4.0.0, November 2022; Swift 5.3).
It only assembles a UA string, which the app already does in two lines via `applicationNameForUserAgent`.
No gap to close, and the dependency is dormant.
Reject.

## Pull-to-refresh (relates to #285)

Issue #285 already concluded the `NSScrollView` bridge must stay until a public pull-to-refresh API ships (none exists through macOS 27; `.refreshable` compiles on macOS but never fires from a gesture).
Both library options are worse than the small tailored bridge we already own:

- **RefreshableScrollView (elegantchaos)** is stale (1.3.1, November 2022) with no clear macOS support.
  It still introspects `NSScrollView` internally, so it relocates rather than removes AppKit, and it is unmaintained.
  Reject.
- **PullToRefreshSwiftUI (shakurocom)** targets iOS 15+ only with no macOS support, so it is not applicable to a macOS-only app.
  Reject.

## Overall recommendation

Adopt none of the candidates at this time.

- **WebUI** is the only library worth tracking.
  It closes #284's capability gaps but relocates AppKit rather than removing it and leaves our `NSWindow` popup code intact, so the trade is a wash against the AppKit-reduction goal.
  Keep our own bridge; revisit alongside #284.
- The **user-agent** and **pull-to-refresh** libraries are stale, iOS-only, or redundant with code we already have.
  Reject.

This matches the issue's bias toward long-term value over saving effort: none of these clears the bar of "maintained dependency that removes work we can't do ourselves."
