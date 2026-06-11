//
//  PadBrowser.swift
//  coderpad
//

import SwiftUI
import WebKit
import AppKit

@Observable
final class WebController: NSObject {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var currentURL: URL?
    private(set) var webView: WKWebView?

    private var observers: [NSKeyValueObservation] = []

    func attach(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView
        observers = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { webView, _ in
                let value = webView.canGoBack
                Task { @MainActor [weak self] in self?.canGoBack = value }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { webView, _ in
                let value = webView.canGoForward
                Task { @MainActor [weak self] in self?.canGoForward = value }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { webView, _ in
                let value = webView.isLoading
                Task { @MainActor [weak self] in self?.isLoading = value }
            },
            webView.observe(\.url, options: [.initial, .new]) { webView, _ in
                let value = webView.url
                Task { @MainActor [weak self] in self?.currentURL = value }
            },
        ]
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let controller: WebController

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        controller.attach(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.attach(webView)
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
        }
        .frame(minWidth: 900, minHeight: 700)
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

            Button { controller.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .accessibilityLabel("Reload page")

            if controller.isLoading {
                ProgressView().controlSize(.small)
            }

            urlLabel
                .layoutPriority(1)

            Spacer(minLength: 8)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
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
