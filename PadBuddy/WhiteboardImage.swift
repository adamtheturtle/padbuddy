//
//  WhiteboardImage.swift
//  coderpad
//

import os
import SafeURLKit
import SwiftUI

/// A remote image downsampled to roughly its display size and cached across view
/// re-creations.
///
/// The whiteboard previously used a bare `AsyncImage`, which decodes the source
/// at full resolution and relies only on the default URL cache — so it re-fetched
/// and re-decoded every time `PadDetailView` was rebuilt (it's keyed `.id(pad.id)`),
/// wasting memory and main-thread decode time on a thumbnail (#375). This fetches
/// through a persistent disk+memory `URLCache`, downsamples with ImageIO off the
/// main actor, and keeps the decoded result in an in-memory cache so re-selecting
/// a pad reuses it instantly.
struct WhiteboardImage: View {
    let url: URL

    @State private var phase: Phase = .loading
    /// Which URL `phase` describes, so a reused view never shows the previous
    /// drawing while the new one loads (#1923).
    @State private var phaseFor: URL?
    /// The in-flight retry, so tapping Retry again replaces it rather than stacking a
    /// second download and decode of the same image (#4604).
    @State private var retryTask: Task<Void, Never>?

    private enum Phase {
        case loading
        case success(PlatformImage, isAnimated: Bool, isStale: Bool)
        case failure
    }

    var body: some View {
        content
            .task(id: url) { await load() }
            .onChange(of: url) { _, _ in
                retryTask?.cancel()
                retryTask = nil
            }
            .onDisappear {
                retryTask?.cancel()
                retryTask = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ZStack {
                Color.subtleStroke
                ProgressView().controlSize(.small)
            }
            .frame(height: 180)
            .accessibilityLabel(Text("Loading whiteboard"))

        case let .success(image, isAnimated, isStale):
            // The enclosing Button carries the "Open the whiteboard full size"
            // label, so the image itself is decorative for VoiceOver.
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if isStale {
                            Label(
                                "Cached image may be out of date",
                                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                            )
                        }
                        if isAnimated {
                            // The inline thumbnail flattens animated formats to their
                            // first frame; say so rather than silently stilling the
                            // drawing (#1927).
                            Label("Animated: open full size to play", systemImage: "play.circle.fill")
                        }
                    }
                    .font(.caption2)
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
                }

        case .failure:
            ZStack {
                Color.subtleStroke
                VStack(spacing: 6) {
                    Label("Could not load whiteboard", systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    // An inline recovery path, so a transient network failure isn't
                    // stuck until the pad is re-selected (#1922, #1930).
                    Button("Retry") { retry() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(height: 120)
        }
    }

    /// Cancels any retry already running for this URL and shows the loading state at once,
    /// so the Retry button cannot be tapped repeatedly to stack concurrent downloads and
    /// decodes of the same large image (#4604).
    private func retry() {
        retryTask?.cancel()
        phase = .loading
        phaseFor = url
        retryTask = Task { await load() }
    }

    private func load() async {
        guard !Task.isCancelled else { return }

        let requestedURL = url
        if phaseFor != url {
            phase = .loading
            phaseFor = url
        }
        // The drawing URL is API data: refuse anything but a plausible HTTPS
        // image host, so a malicious or misconfigured record can't point the app
        // at loopback, LAN, or plaintext resources (#1158).
        guard Self.isAllowedImageURL(url) else {
            phase = .failure
            return
        }

        // The whiteboard renders into the detail pane (a few hundred points wide)
        // and opens full size on tap, so cap the inline copy at a generous pane
        // width in pixels rather than decoding the source at full resolution.
        let scale = PlatformScreen.backingScaleFactor
        let maxPixelSize = Int(600 * scale)
        let request = WhiteboardImageCache.request(url: url, maxPixelSize: maxPixelSize)

        let cached = WhiteboardImageCache.shared.image(for: request)
        if let cached {
            // Show the cached thumbnail instantly, but keep going: the drawing can
            // change behind an unchanged URL, so every load revalidates through the
            // URL cache (conditional GET when the server offers validators) and
            // refreshes the decoded copy (#792).
            let isFresh = WhiteboardImageCache.isFresh(storedAt: cached.storedAt)
            phase = .success(cached.image, isAnimated: cached.isAnimated, isStale: !isFresh)
            // Except while the entry is still brand new: `.task(id: url)` re-fires on
            // every remount, and PadDetailView is keyed `.id(pad.id)`, so flicking
            // between pads paid a round-trip and an off-main re-decode per
            // reselection for a thumbnail that was just validated (#2096). The window
            // is short enough that #792's "the drawing changed behind the URL" case
            // still resolves on the next look.
            if isFresh {
                return
            }
        }

        do {
            let loadRequest = WhiteboardImageCache.request(
                url: url, maxPixelSize: maxPixelSize, revalidating: cached != nil
            )
            let loaded = try await WhiteboardImageCache.shared.load(loadRequest)
            // `.task(id: url)` cancelled this task if the URL moved on; a late
            // result must not overwrite the newer URL's image (#793).
            try Task.checkCancellation()
            guard phaseFor == requestedURL else { return }

            withAnimation(cached == nil ? .default : nil) {
                phase = .success(loaded.image, isAnimated: loaded.isAnimated, isStale: false)
            }
        } catch {
            guard !Task.isCancelled, phaseFor == requestedURL else { return }

            // A failed revalidation keeps showing the cached thumbnail rather than
            // flashing a failure over a perfectly presentable image — but it is
            // logged, not swallowed (#1561, #1930).
            // `.private`: URL-loading errors commonly embed the failing URL, and whiteboard
            // export URLs carry their signature in the query (#4602).
            WhiteboardImageCache.logger.error(
                "Whiteboard load failed: \(error.localizedDescription, privacy: .private)"
            )
            if cached == nil {
                phase = .failure
            }
        }
    }

    /// The whiteboard thumbnail's download budget. The rendered copy is capped at
    /// 600 points, so anything past this is either a mistake or a resource-
    /// exhaustion attempt (#1159).
    static let maxDownloadBytes = 20 * 1024 * 1024

    /// Whether `url` is a plausibly safe remote image source: HTTPS only, with a
    /// hostname that isn't loopback, mDNS-local, or an IP literal — drawing
    /// exports are served from hostnames, and a literal is how a malicious
    /// record reaches loopback or the LAN (#1158).
    ///
    /// The mechanism is SafeURLKit's (#1866). The hand-rolled literal check this
    /// replaced only recognised dotted-decimal, so `0x7f.1`, `2130706433`, and
    /// `[::ffff:169.254.169.254]` all read as ordinary hostnames to it.
    ///
    /// No origin allow-list: whiteboard exports are served from whatever host the
    /// account's deployment uses, so the constraint is on what kind of host it may
    /// be, not which one. A query is allowed because export URLs are typically
    /// signed and carry their signature there.
    nonisolated static let imageURLPolicy = URLPolicy(
        allowedSchemes: ["https"],
        portRule: .defaultForScheme
    )

    nonisolated static func isAllowedImageURL(_ url: URL) -> Bool {
        imageURLPolicy.allows(url)
    }
}
