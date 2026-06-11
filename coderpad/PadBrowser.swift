//
//  PadBrowser.swift
//  coderpad
//

import SwiftUI
import WebKit
import AppKit

/// Safari's user-agent suffix. Google blocks its OAuth consent screen for user
/// agents it doesn't recognize as a full browser ("disallowed_useragent"), so we
/// append the "Version/… Safari/…" suffix the default WKWebView UA omits, on every
/// web view including JavaScript-opened popups. Note: this does NOT enable the
/// system Passwords app / iCloud Keychain autofill — Apple gates that to apps
/// recognized as browsers, and an embedded WKWebView never qualifies. It only
/// keeps Google happy and helps Accessibility-based managers (e.g. 1Password's
/// ⌘\ universal autofill) recognize the field.
let safariUserAgentSuffix = "Version/17.6 Safari/605.1.15"

@Observable
final class WebController: NSObject {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var currentURL: URL?

    /// A human-readable description of the most recent load failure, or `nil` when
    /// the page loaded (or is still loading). The browser view shows an error overlay
    /// while this is set so a failed load is visible and recoverable instead of just
    /// a blank web view. Cleared the moment a new navigation starts or one succeeds.
    var loadFailure: String?

    private(set) var webView: WKWebView?

    private var observers: [NSKeyValueObservation] = []

    /// Windows hosting JavaScript-opened popups (e.g. the "Sign in with Google"
    /// OAuth window). A bare `WKWebView` ignores `window.open`, so without this the
    /// popup silently never appears. We retain each popup's window here so we can
    /// close it when the page calls `window.close()` or the user closes it.
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]

    /// The URL we asked the web view to show. WebKit occasionally drops the very
    /// first navigation (e.g. the content process wasn't ready) or hits a transient
    /// network failure, either of which leaves the user staring at a blank page with
    /// no error. We keep the requested URL so the navigation delegate can retry it
    /// once. `didRetryLoad` makes the retry one-shot so a genuinely unreachable page
    /// doesn't reload forever.
    private var requestedURL: URL?
    private var didRetryLoad = false

    /// Load `url`, recording it so a dropped or failed navigation can be retried.
    func load(_ url: URL) {
        requestedURL = url
        didRetryLoad = false
        loadFailure = nil
        webView?.load(URLRequest(url: url))
    }

    /// Reload the URL the user actually asked for (not `webView.url`, which may be an
    /// error or `about:blank` after a failure). Used by the error overlay's retry.
    func retryRequestedURL() {
        if let requestedURL {
            load(requestedURL)
        } else {
            webView?.reload()
        }
    }

    func attach(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView
        observers = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                let value = webView.canGoBack
                Task { @MainActor in self?.canGoBack = value }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                let value = webView.canGoForward
                Task { @MainActor in self?.canGoForward = value }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                let value = webView.isLoading
                Task { @MainActor in self?.isLoading = value }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                let value = webView.url
                Task { @MainActor in self?.currentURL = value }
            },
        ]
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    /// Hard refresh: purge WebKit's cached resources, then reload from the origin
    /// bypassing the HTTP cache. The plain `reload()` revalidates conditionally and
    /// can still serve cached bytes; this guarantees a fresh fetch from the server,
    /// which is what users reach for when a page is stuck on stale content.
    func hardReload() {
        guard let webView else { return }
        let dataStore = webView.configuration.websiteDataStore
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache,
        ]
        dataStore.removeData(ofTypes: cacheTypes, modifiedSince: .distantPast) {
            webView.reloadFromOrigin()
        }
    }

    /// Clear the browsing session: purge cookies and web storage, then reload. Login
    /// state lives in cookies and local/session storage rather than the HTTP cache,
    /// so a plain hard refresh leaves you signed in. This logs you out of the Pad,
    /// matching what clearing site data does in a regular browser.
    func clearSession() {
        guard let webView else { return }
        let dataStore = webView.configuration.websiteDataStore
        let sessionTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
        ]
        dataStore.removeData(ofTypes: sessionTypes, modifiedSince: .distantPast) {
            webView.reloadFromOrigin()
        }
    }
}

// MARK: - Popups & JavaScript dialogs

extension WebController: WKUIDelegate, NSWindowDelegate {
    /// Handle `window.open(...)` requests. Sign-in flows like "Sign in with Google"
    /// open their consent screen in a popup; with no UI delegate WebKit drops the
    /// request entirely and nothing appears. We create a real popup web view sharing
    /// the opener's configuration (so the `window.opener` postMessage handshake that
    /// completes the sign-in keeps working) and host it in its own window.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            // WebKit hands us a fresh configuration for the popup that does not
            // inherit the opener's `applicationNameForUserAgent`. Re-apply the
            // Safari suffix so Google doesn't reject the OAuth window and so
            // Accessibility-based password managers recognize it as a browser
            // field. (The system Passwords app still won't fill an embedded
            // WKWebView — see `safariUserAgentSuffix`.)
            configuration.applicationNameForUserAgent = safariUserAgentSuffix

            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.uiDelegate = self

            let width = windowFeatures.width?.doubleValue ?? 600
            let height = windowFeatures.height?.doubleValue ?? 720
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Sign In"
            window.contentView = popup
            window.delegate = self
            window.center()
            window.makeKeyAndOrderFront(nil)
            // Put the popup web view in the responder chain immediately so the
            // sign-in field is focusable and the autofill affordance engages
            // without the user first having to click into the window.
            window.makeFirstResponder(popup)

            popupWindows[ObjectIdentifier(popup)] = window
            return popup
        }
    }

    /// The page asked to close its popup (the OAuth window does this once it has
    /// handed the credential back to the opener).
    func webViewDidClose(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            let key = ObjectIdentifier(webView)
            popupWindows[key]?.close()
            popupWindows[key] = nil
        }
    }

    /// Drop our reference when the user closes a popup manually.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        popupWindows = popupWindows.filter { $0.value !== window }
    }

    // Surface JavaScript dialogs natively so pages that rely on them (some sign-in
    // flows show confirm/alert prompts) behave instead of silently no-opping.

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}

// MARK: - Navigation failures

extension WebController: WKNavigationDelegate {
    /// A new navigation started — clear any stale failure so the error overlay
    /// disappears while we try again.
    func webView(_ webView: WKWebView,
                 didStartProvisionalNavigation navigation: WKNavigation!) {
        MainActor.assumeIsolated { loadFailure = nil }
    }

    /// The page loaded. Clear the failure state.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { loadFailure = nil }
    }

    /// The initial request never produced a page. This is the common "blank pad"
    /// symptom: a dropped first navigation or a transient network error. Retry the
    /// requested URL once before surfacing the error.
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        retryOrReport(error)
    }

    /// A committed navigation failed partway through. Same one-shot retry.
    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        retryOrReport(error)
    }

    private func retryOrReport(_ error: Error) {
        // A user- or script-cancelled navigation (e.g. a redirect superseding the
        // request) isn't a failure to recover from — reloading would fight the page.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

        // First failure: retry the requested URL once after a short beat.
        guard let url = requestedURL else {
            MainActor.assumeIsolated { loadFailure = error.localizedDescription }
            return
        }
        if !didRetryLoad {
            didRetryLoad = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.webView?.load(URLRequest(url: url))
            }
            return
        }
        // Retry also failed — surface it so the user sees an error instead of a blank.
        MainActor.assumeIsolated { loadFailure = error.localizedDescription }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let controller: WebController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Identify as Safari so Google serves its OAuth screen and password
        // managers offer autofill. See `safariUserAgentSuffix` for the rationale;
        // the same value is re-applied to sign-in popups in the UI delegate.
        configuration.applicationNameForUserAgent = safariUserAgentSuffix

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = controller
        webView.navigationDelegate = controller
        controller.attach(webView)
        controller.load(url)
        context.coordinator.loadedURL = url
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.attach(webView)
        // SwiftUI reuses this web view when the bound `url` changes — e.g. opening a
        // second pad into the existing "pad-browser" window, or switching the
        // selected pad while the in-app browser is open. `makeNSView` only loads the
        // first URL, so without this the view keeps showing the original (now blank
        // or stale) page. Reload only on an actual change so we don't clobber the
        // user's in-page navigation on every SwiftUI update.
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            controller.load(url)
        }
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

struct PadBrowserView: View {
    let url: URL
    @State private var controller = WebController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            WebViewRepresentable(url: url, controller: controller)
                .overlay {
                    if let failure = controller.loadFailure {
                        loadErrorOverlay(failure)
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 700)
    }

    /// Shown over the (blank) web view when a load fails after the automatic retry,
    /// turning an invisible failure into something the user can act on.
    private func loadErrorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Couldn’t load this pad")
                    .font(.title3.bold())
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button {
                    controller.retryRequestedURL()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    BrowserSettings.openExternally(controller.currentURL ?? url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { controller.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!controller.canGoBack)
            .help("Back")
            .accessibilityLabel("Back")

            Button { controller.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!controller.canGoForward)
            .help("Forward")
            .accessibilityLabel("Forward")

            // Plain reload, with Option-click escalating to a no-cache hard refresh.
            // A right-click menu and the ⇧⌘R shortcut below expose the same options
            // for discoverability.
            Button {
                if NSEvent.modifierFlags.contains(.option) {
                    controller.hardReload()
                } else {
                    controller.reload()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload (hold ⌥ to reload without cache)")
            .accessibilityLabel("Reload page")
            .contextMenu {
                Button("Reload") { controller.reload() }
                Button("Reload Without Cache") { controller.hardReload() }
                Divider()
                Button("Clear Session (Log Out)") { controller.clearSession() }
            }

            Button { controller.clearSession() } label: {
                Image(systemName: "person.crop.circle.badge.xmark")
            }
            .help("Clear session: log out of the Pad by clearing cookies and storage")
            .accessibilityLabel("Clear session and log out")

            if controller.isLoading {
                ProgressView().controlSize(.small)
            }

            urlLabel
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            Button {
                BrowserSettings.openExternally(controller.currentURL ?? url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
                    .fixedSize()
            }
            .help("Open the current page in your default browser")

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString((controller.currentURL ?? url).absoluteString, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy URL")
            .accessibilityLabel("Copy URL")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .background {
            // Hidden buttons carrying the reload keyboard shortcuts: ⌘R for a normal
            // reload and ⇧⌘R for a hard, cache-bypassing refresh.
            Group {
                Button("Reload") { controller.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Reload Without Cache") { controller.hardReload() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            .hidden()
        }
    }

    private var urlLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: lockIcon)
                .foregroundStyle(lockTint)
                .font(.caption)
            Text(controller.currentURL?.absoluteString ?? url.absoluteString)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.subtleStroke.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var lockIcon: String {
        ((controller.currentURL ?? url).scheme ?? "").lowercased() == "https" ? "lock" : "lock.open"
    }
    private var lockTint: Color {
        ((controller.currentURL ?? url).scheme ?? "").lowercased() == "https" ? .green : .orange
    }
}
