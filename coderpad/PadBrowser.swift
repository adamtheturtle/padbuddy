//
//  PadBrowser.swift
//  coderpad
//

import AppKit
import SwiftUI
import WebKit

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
            }
        ]
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

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
            WKWebsiteDataTypeFetchCache
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
            WKWebsiteDataTypeWebSQLDatabases
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
    func webView(_: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for _: WKNavigationAction,
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

    func webView(_: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame _: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }
    }

    func webView(_: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame _: WKFrameInfo,
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
    func webView(_: WKWebView,
                 didStartProvisionalNavigation _: WKNavigation!) {
        MainActor.assumeIsolated { loadFailure = nil }
    }

    /// The page loaded. Clear the failure state.
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        MainActor.assumeIsolated { loadFailure = nil }
    }

    /// The initial request never produced a page. This is the common "blank pad"
    /// symptom: a dropped first navigation or a transient network error. Retry the
    /// requested URL once before surfacing the error.
    func webView(_: WKWebView,
                 didFailProvisionalNavigation _: WKNavigation!,
                 withError error: Error) {
        retryOrReport(error)
    }

    /// A committed navigation failed partway through. Same one-shot retry.
    func webView(_: WKWebView,
                 didFail _: WKNavigation!,
                 withError error: Error) {
        retryOrReport(error)
    }

    private func retryOrReport(_ error: Error) {
        // A user- or script-cancelled navigation (e.g. a redirect superseding the
        // request) isn't a failure to recover from — reloading would fight the page.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }

        // First failure: retry the requested URL once after a short beat.
        guard let url = requestedURL else {
            MainActor.assumeIsolated { loadFailure = error.localizedDescription }
            return
        }
        if !didRetryLoad {
            didRetryLoad = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.webView?.load(URLRequest(url: url))
            }
            return
        }
        // Retry also failed — surface it so the user sees an error instead of a blank.
        MainActor.assumeIsolated { loadFailure = error.localizedDescription }
    }
}
