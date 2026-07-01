//
//  PadBrowser+Views.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI
import WebKit

#if os(macOS)
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
#else
    struct WebViewRepresentable: UIViewRepresentable {
        let url: URL
        let controller: WebController

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> WKWebView {
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

        func updateUIView(_ webView: WKWebView, context: Context) {
            controller.attach(webView)
            // SwiftUI reuses this web view when the bound `url` changes — e.g. opening a
            // second pad into the existing "pad-browser" window, or switching the
            // selected pad while the in-app browser is open. `makeUIView` only loads the
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
#endif

struct PadBrowserView: View {
    let url: URL
    @State private var controller = WebController()
    /// Fade the loading spinner only when Reduce Motion allows it (#628).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The load-failure icon's point size, scaled with the user's preferred text
    /// size (tracking Large Title) so it honors the accessibility setting.
    @ScaledMetric(relativeTo: .largeTitle) private var errorIconSize: CGFloat = 40

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
        // Advertise the live pad for Handoff / Spotlight / Siri (#596). Track the
        // web view's in-page navigation so the activity always reflects the URL the
        // user is actually looking at, not just the one it opened with.
        .advertisesPadActivity(url: controller.currentURL ?? url, title: controller.pageTitle)
        // No minimum size here: when embedded in the detail pane this view must fit
        // the (narrower) column, otherwise a 900pt floor pushes the toolbar wider
        // than the column and clips its trailing controls. The standalone Pad Browser
        // window applies its own minimum at the call site.
    }

    /// Shown over the (blank) web view when a load fails after the automatic retry,
    /// turning an invisible failure into something the user can act on.
    private func loadErrorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: errorIconSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Couldn’t load this pad")
                    .font(.title3.bold())
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Spacing.controlGap) {
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
        .padding(Spacing.overlayInset)
        .frame(maxWidth: 420)
        .floatingGlass(
            in: RoundedRectangle(cornerRadius: Radius.prominent, style: .continuous),
            fallback: .regularMaterial
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var toolbar: some View {
        GlassCluster(spacing: 8) {
            HStack(spacing: 8) {
                backButton
                forwardButton
                reloadButton
                // macOS keeps Clear Session inline; on iPad it moves to the trailing
                // overflow menu so the narrow detail-column bar isn't crowded.
                #if os(macOS)
                    clearSessionButton
                #endif

                // Keep the loading spinner a permanent member of the glass cluster and
                // drive only its opacity (#590). Inserting/removing it on every
                // `isLoading` toggle - which the WKWebView KVO can fire more than once
                // per frame during a load - changed the `GlassEffectContainer`'s child
                // set repeatedly within a frame, forcing it to re-resolve its glass
                // shapes and logging a "glassEffect() tried to update multiple times per
                // frame" fault. Opacity changes leave the container's membership stable.
                ProgressView()
                    .controlSize(.small)
                    .opacity(controller.isLoading ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: controller.isLoading)

                urlLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                // The secondary actions (Passwords, Open in Browser, Copy URL — plus
                // Clear Session and a hard reload) stay as their own buttons in the wide
                // macOS window, but collapse into a single ellipsis menu on iPad, where
                // the detail column is too narrow to hold seven icons and the URL. This
                // is the standard Safari-on-iPad compact layout.
                #if os(macOS)
                    passwordsButton
                    openExternalButton
                    copyURLButton
                #else
                    overflowMenu
                #endif
            }
            // Each control becomes its own Liquid Glass element on macOS 26, blending
            // and morphing as a cluster via the enclosing GlassCluster. The bar itself
            // stays a plain material so the glass refracts content rather than stacking
            // glass-on-glass.
            .glassButtonStyle()
        }
        .padding(.horizontal, Spacing.bannerH)
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

    private var backButton: some View {
        Button { controller.goBack() } label: {
            Image(systemName: "chevron.left")
        }
        .disabled(!controller.canGoBack)
        .help("Back")
        .accessibilityLabel("Back")
    }

    private var forwardButton: some View {
        Button { controller.goForward() } label: {
            Image(systemName: "chevron.right")
        }
        .disabled(!controller.canGoForward)
        .help("Forward")
        .accessibilityLabel("Forward")
    }

    /// Plain reload, with Option-click escalating to a no-cache hard refresh on macOS.
    /// A right-click/long-press menu and the ⇧⌘R shortcut expose the same options.
    private var reloadButton: some View {
        Button {
            #if os(macOS)
                // Option-click escalates to a no-cache hard refresh. There is no
                // iOS equivalent for reading the modifier on tap, so iPad gets the
                // plain reload (the context menu still exposes a hard refresh).
                if NSEvent.modifierFlags.contains(.option) {
                    controller.hardReload()
                } else {
                    controller.reload()
                }
            #else
                controller.reload()
            #endif
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
    }

    private var clearSessionButton: some View {
        Button { controller.clearSession() } label: {
            Image(systemName: "person.crop.circle.badge.xmark")
        }
        .help("Clear session: log out of the Pad by clearing cookies and storage")
        .accessibilityLabel("Clear session and log out")
    }

    /// Native Passwords/iCloud Keychain autofill can't appear in an embedded
    /// WKWebView, so offer manual help: open the Passwords app to look up and
    /// copy a login to paste into the field.
    private var passwordsButton: some View {
        Button { BrowserSettings.openPasswordsApp() } label: {
            Image(systemName: "key.fill")
        }
        .help("Open the Passwords app to look up and copy a login")
        .accessibilityLabel("Open Passwords")
    }

    private var openExternalButton: some View {
        Button {
            BrowserSettings.openExternally(controller.currentURL ?? url)
        } label: {
            // Show the full label in the wide standalone Pad Browser window, but
            // collapse to the icon alone when embedded in the narrower detail
            // column so this and the trailing Copy button aren't clipped off the
            // right edge.
            ViewThatFits(in: .horizontal) {
                Label("Open in Browser", systemImage: "safari")
                    .fixedSize()
                Image(systemName: "safari")
            }
        }
        .help("Open the current page in your default browser")
        .accessibilityLabel("Open in Browser")
    }

    private var copyURLButton: some View {
        Button {
            Clipboard.copy((controller.currentURL ?? url).absoluteString)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .help("Copy URL")
        .accessibilityLabel("Copy URL")
    }

    /// iPad-only: the secondary browser actions folded into one trailing menu, so the
    /// narrow detail-column toolbar shows just Back/Forward/Reload, the address, and
    /// this ellipsis — the Safari-on-iPad layout — instead of clipping seven icons.
    private var overflowMenu: some View {
        Menu {
            Button { BrowserSettings.openExternally(controller.currentURL ?? url) } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            Button { Clipboard.copy((controller.currentURL ?? url).absoluteString) } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            Button { BrowserSettings.openPasswordsApp() } label: {
                Label("Passwords", systemImage: "key.fill")
            }
            Divider()
            Button { controller.hardReload() } label: {
                Label("Reload Without Cache", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) { controller.clearSession() } label: {
                Label("Clear Session (Log Out)", systemImage: "person.crop.circle.badge.xmark")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More browser actions")
        .accessibilityLabel("More browser actions")
    }

    private var urlLabel: some View {
        let address = controller.currentURL?.absoluteString ?? url.absoluteString
        // Localize the spoken security state itself (#624): as a literal interpolated
        // into the label below it was formatted as a value and never entered the catalog.
        let security = isSecure ? String(localized: "Secure") : String(localized: "Not secure")
        return HStack(spacing: 6) {
            Image(systemName: lockIcon)
                .foregroundStyle(lockTint)
                .font(.caption)
            Text(address)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.compactControlH)
        .padding(.vertical, 4)
        .background(Color.subtleStroke.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        // The lock is icon- and color-only, so VoiceOver would otherwise announce a
        // bare symbol name and miss the security state entirely. Read the bar as one
        // element that names whether the connection is secure, then the address (#79).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(security), \(address)")
    }

    /// Whether the displayed page is loaded over HTTPS, driving both the lock glyph
    /// and its tint (and the spoken security state above).
    private var isSecure: Bool {
        ((controller.currentURL ?? url).scheme ?? "").lowercased() == "https"
    }

    private var lockIcon: String {
        isSecure ? "lock" : "lock.open"
    }

    private var lockTint: Color {
        isSecure ? .green : .orange
    }
}
