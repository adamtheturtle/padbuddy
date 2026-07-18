//
//  WhiteboardImage.swift
//  coderpad
//

import ImageIO
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

    private enum Phase {
        case loading
        case success(PlatformImage)
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

        case let .success(image):
            // The enclosing Button carries the "Open the whiteboard full size"
            // label, so the image itself is decorative for VoiceOver.
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)

        case .failure:
            ZStack {
                Color.subtleStroke
                Label("Couldn’t load whiteboard", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(height: 120)
        }
    }

    private func load() async {
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
        let key = "\(url.absoluteString)|\(maxPixelSize)"

        let cached = WhiteboardImageCache.shared.image(forKey: key)
        if let cached {
            // Show the cached thumbnail instantly, but keep going: the drawing can
            // change behind an unchanged URL, so every load revalidates through the
            // URL cache (conditional GET when the server offers validators) and
            // refreshes the decoded copy (#792).
            phase = .success(cached)
        } else {
            phase = .loading
        }

        do {
            let data = try await Self.fetchBounded(
                url: url,
                maxBytes: Self.maxDownloadBytes,
                session: WhiteboardImageCache.shared.session
            )
            // Don't start a decode for a view that's already gone: the detached
            // task below outlives cancellation once started, so rapid pad
            // switching would otherwise pile up full decodes (#1160).
            try Task.checkCancellation()
            // Downsample off the main actor; ImageIO does the heavy decode.
            let downsampled = await Task.detached(priority: .utility) {
                WhiteboardImageCache.downsample(data: data, maxPixelSize: maxPixelSize)
            }.value
            // `.task(id: url)` cancelled this task if the URL moved on, but the
            // detached downsample doesn't inherit that: a late result must not
            // overwrite the newer URL's image (#793).
            try Task.checkCancellation()
            guard let image = downsampled?.image else {
                if cached == nil { phase = .failure }
                return
            }

            WhiteboardImageCache.shared.store(image, forKey: key)
            phase = .success(image)
        } catch {
            guard !Task.isCancelled else { return }

            // A failed revalidation keeps showing the cached thumbnail rather than
            // flashing a failure over a perfectly presentable image.
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
    nonisolated static func isAllowedImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), !host.isEmpty,
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local")
        else { return false }

        let isIPv4Literal = host.contains(".") && host.allSatisfy { $0.isNumber || $0 == "." }
        let isIPv6Literal = host.contains(":")
        return !isIPv4Literal && !isIPv6Literal
    }

    /// Streams the response, rejecting it as soon as it exceeds `maxBytes`: the
    /// eventual thumbnail is pixel-capped, and downloading an unbounded body
    /// first would let a large or malicious response exhaust memory and
    /// bandwidth anyway (#1159). Nonisolated so the byte loop runs off the main
    /// actor; URLSession still populates the shared `URLCache` for the
    /// revalidation path (#792).
    nonisolated private static func fetchBounded(
        url: URL,
        maxBytes: Int,
        session: URLSession
    ) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
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
}

/// Shared cache + loader for whiteboard thumbnails: a persistent `URLCache` for the
/// source bytes and an in-memory map of the decoded, downsampled images. Confined
/// to the main actor since only the whiteboard view (on the main actor) touches it.
@MainActor
final class WhiteboardImageCache {
    static let shared = WhiteboardImageCache()

    // Decoded, downsampled thumbnails. Each is a few MB of uncompressed bitmap, so an
    // uncapped map grew without bound across a long session of viewing whiteboards
    // (#422, a cause of #418). NSCache bounds it by count and also evicts automatically
    // under memory pressure — the idiomatic fit for a decoded-image cache.
    // swiftlint:disable:next legacy_objc_type
    private let memory: NSCache<NSString, PlatformImage> = {
        // swiftlint:disable:next legacy_objc_type
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 32
        return cache
    }()

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
        session = URLSession(configuration: config)
    }

    func image(forKey key: String) -> PlatformImage? {
        // swiftlint:disable:next legacy_objc_type
        memory.object(forKey: key as NSString)
    }

    func store(_ image: PlatformImage, forKey key: String) {
        // swiftlint:disable:next legacy_objc_type
        memory.setObject(image, forKey: key as NSString)
    }

    /// A box so the immutable, freshly decoded image can cross the actor boundary
    /// out of the detached downsample task under strict concurrency.
    struct DownsampledImage: @unchecked Sendable {
        let image: PlatformImage
    }

    /// Decode `data` to an image no larger than `maxPixelSize` on its longest edge
    /// using ImageIO's thumbnail path, so a large whiteboard never decodes at full
    /// resolution for an inline thumbnail.
    nonisolated static func downsample(data: Data, maxPixelSize: Int) -> DownsampledImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
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
        return DownsampledImage(image: image)
    }
}
