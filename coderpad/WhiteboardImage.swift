//
//  WhiteboardImage.swift
//  coderpad
//

import CryptoKit
import ImageIO
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

    private enum Phase {
        case loading
        case success(PlatformImage, isAnimated: Bool)
        case failure
    }

    var body: some View {
        content
            .task(id: url) { await load() }
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

        case let .success(image, isAnimated):
            // The enclosing Button carries the "Open the whiteboard full size"
            // label, so the image itself is decorative for VoiceOver.
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
                .overlay(alignment: .bottomTrailing) {
                    if isAnimated {
                        // The inline thumbnail flattens animated formats to their
                        // first frame; say so rather than silently stilling the
                        // drawing (#1927).
                        Label("Animated: open full size to play", systemImage: "play.circle.fill")
                            .font(.caption2)
                            .padding(4)
                            .background(.thinMaterial, in: Capsule())
                            .padding(6)
                    }
                }

        case .failure:
            ZStack {
                Color.subtleStroke
                VStack(spacing: 6) {
                    Label("Couldn’t load whiteboard", systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    // An inline recovery path, so a transient network failure isn't
                    // stuck until the pad is re-selected (#1922, #1930).
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(height: 120)
        }
    }

    private func load() async {
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
        let key = WhiteboardImageCache.cacheKey(url: url, maxPixelSize: maxPixelSize)

        let cached = WhiteboardImageCache.shared.image(forKey: key)
        if let cached {
            // Show the cached thumbnail instantly, but keep going: the drawing can
            // change behind an unchanged URL, so every load revalidates through the
            // URL cache (conditional GET when the server offers validators) and
            // refreshes the decoded copy (#792).
            phase = .success(cached.image, isAnimated: cached.isAnimated)
        }

        do {
            let downsampled = try await WhiteboardImageCache.shared.loadDownsampled(
                url: url, maxPixelSize: maxPixelSize, key: key
            )
            // `.task(id: url)` cancelled this task if the URL moved on; a late
            // result must not overwrite the newer URL's image (#793).
            try Task.checkCancellation()
            guard let downsampled else {
                if cached == nil { phase = .failure }
                return
            }

            let entry = WhiteboardImageCache.Entry(image: downsampled.image, isAnimated: downsampled.isAnimated)
            WhiteboardImageCache.shared.store(entry, forKey: key)
            withAnimation(cached == nil ? .default : nil) {
                phase = .success(downsampled.image, isAnimated: downsampled.isAnimated)
            }
        } catch {
            guard !Task.isCancelled else { return }

            // A failed revalidation keeps showing the cached thumbnail rather than
            // flashing a failure over a perfectly presentable image — but it is
            // logged, not swallowed (#1561, #1930).
            WhiteboardImageCache.logger.error(
                "Whiteboard load failed: \(error.localizedDescription, privacy: .public)"
            )
            if cached == nil { phase = .failure }
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

/// Shared cache + loader for whiteboard thumbnails: a persistent `URLCache` for the
/// source bytes and an in-memory map of the decoded, downsampled images. Confined
/// to the main actor since only the whiteboard view (on the main actor) touches it.
@MainActor
final class WhiteboardImageCache {
    static let shared = WhiteboardImageCache()
    nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "whiteboard")

    /// A decoded thumbnail plus whether its source had multiple frames, boxed for
    /// `NSCache` (which stores objects, not tuples).
    final class Entry {
        let image: PlatformImage
        let isAnimated: Bool

        init(image: PlatformImage, isAnimated: Bool) {
            self.image = image
            self.isAnimated = isAnimated
        }
    }

    // Decoded, downsampled thumbnails. Each is a few MB of uncompressed bitmap, so an
    // uncapped map grew without bound across a long session of viewing whiteboards
    // (#422, a cause of #418). NSCache bounds it by count AND by decoded byte cost
    // (#1560, #1919), and also evicts automatically under memory pressure.
    // swiftlint:disable:next legacy_objc_type
    private let memory: NSCache<NSString, Entry> = {
        // swiftlint:disable:next legacy_objc_type
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 32
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// Fetch-and-decode tasks in flight, keyed like the memory cache, so several
    /// concurrently mounted views of one drawing share a single download and decode
    /// instead of duplicating both (#1920).
    private var inFlight: [String: Task<DownsampledImage?, any Error>] = [:]

    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // Persist source bytes across launches and re-selections so the whiteboard
        // isn't re-fetched every time PadDetailView is rebuilt. The default cache
        // directory lives in the sandbox container's Caches, which is writable.
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                   diskCapacity: 64 * 1024 * 1024,
                                   directory: nil)
        // Standard HTTP semantics rather than returnCacheDataElseLoad: an edited
        // drawing can be served behind an unchanged URL, and blindly reusing cached
        // bytes froze it forever (#792). With validators this is a cheap conditional
        // GET; the decoded memory cache still makes re-selection instant.
        config.requestCachePolicy = .useProtocolCachePolicy
        // Explicit time bounds to go with the byte bound: a stalled or trickling
        // response must not hold the slot open indefinitely (#1924).
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    /// The cache identity for one drawing at one pixel cap. Hashed, so signed or
    /// token-bearing image URLs aren't retained verbatim in long-lived cache keys
    /// (#1557, #1925); the pixel size keys per display scale.
    nonisolated static func cacheKey(url: URL, maxPixelSize: Int) -> String {
        let digest = SHA256.hash(data: Data("\(url.absoluteString)|\(maxPixelSize)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func image(forKey key: String) -> Entry? {
        // swiftlint:disable:next legacy_objc_type
        memory.object(forKey: key as NSString)
    }

    func store(_ entry: Entry, forKey key: String) {
        let pixels = entry.image.size.width * entry.image.size.height
        // swiftlint:disable:next legacy_objc_type
        memory.setObject(entry, forKey: key as NSString, cost: Int(pixels) * 4)
    }

    /// Fetches (bounded, validated) and downsamples one drawing, coalescing
    /// concurrent requests for the same key (#1920). A caller whose view goes away
    /// just stops awaiting; the shared work finishes for the remaining callers.
    func loadDownsampled(url: URL, maxPixelSize: Int, key: String) async throws -> DownsampledImage? {
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let session = session
        let task = Task {
            let data = try await Self.fetchBounded(
                url: url, maxBytes: WhiteboardImage.maxDownloadBytes, session: session
            )
            // Downsample off the main actor; ImageIO does the heavy decode.
            return await Task.detached(priority: .utility) {
                Self.downsample(data: data, maxPixelSize: maxPixelSize)
            }.value
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Streams the response, rejecting it as soon as it exceeds `maxBytes`: the
    /// eventual thumbnail is pixel-capped, and downloading an unbounded body
    /// first would let a large or malicious response exhaust memory and
    /// bandwidth anyway (#1159). Only successful image responses count: an error
    /// page or non-image payload must not reach the decoder (#1918). Nonisolated
    /// so the byte loop runs off the main actor; URLSession still populates the
    /// shared `URLCache` for the revalidation path (#792).
    private nonisolated static func fetchBounded(
        url: URL,
        maxBytes: Int,
        session: URLSession
    ) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard response.mimeType?.lowercased().hasPrefix("image/") ?? false else {
            throw URLError(.cannotDecodeContentData)
        }

        if response.expectedContentLength > 0, response.expectedContentLength > Int64(maxBytes) {
            throw URLError(.dataLengthExceedsMaximum)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(min(response.expectedContentLength, Int64(maxBytes))))
        }
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        }
        return data
    }

    /// A box so the immutable, freshly decoded image can cross the actor boundary
    /// out of the detached downsample task under strict concurrency.
    struct DownsampledImage: @unchecked Sendable {
        let image: PlatformImage
        let isAnimated: Bool
    }

    /// The largest source canvas the decoder will accept on either edge: a
    /// plausible drawing is far smaller, and a decompression-bomb canvas is how a
    /// malicious record turns a small download into gigabytes of bitmap (#1556).
    nonisolated static let maxSourcePixelsPerEdge = 20000

    /// Decode `data` to an image no larger than `maxPixelSize` on its longest edge
    /// using ImageIO's thumbnail path, so a large whiteboard never decodes at full
    /// resolution for an inline thumbnail. Sources with implausible or missing
    /// pixel dimensions are rejected before any decode (#1556).
    nonisolated static func downsample(data: Data, maxPixelSize: Int) -> DownsampledImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              width <= maxSourcePixelsPerEdge, height <= maxSourcePixelsPerEdge else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = PlatformImage.fromCGImage(cgImage)
        return DownsampledImage(image: image, isAnimated: CGImageSourceGetCount(source) > 1)
    }
}
