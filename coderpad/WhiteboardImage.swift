//
//  WhiteboardImage.swift
//  coderpad
//

import AppKit
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
        case success(NSImage)
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
            Image(nsImage: image)
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
        phase = .loading

        // The whiteboard renders into the detail pane (a few hundred points wide)
        // and opens full size on tap, so cap the inline copy at a generous pane
        // width in pixels rather than decoding the source at full resolution.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixelSize = Int(600 * scale)
        let key = "\(url.absoluteString)|\(maxPixelSize)"

        if let cached = WhiteboardImageCache.shared.image(forKey: key) {
            phase = .success(cached)
            return
        }

        do {
            let (data, _) = try await WhiteboardImageCache.shared.session.data(from: url)
            // Downsample off the main actor; ImageIO does the heavy decode.
            let downsampled = await Task.detached {
                WhiteboardImageCache.downsample(data: data, maxPixelSize: maxPixelSize)
            }.value
            guard let image = downsampled?.image else {
                phase = .failure
                return
            }

            WhiteboardImageCache.shared.store(image, forKey: key)
            phase = .success(image)
        } catch {
            phase = .failure
        }
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
    private let memory: NSCache<NSString, NSImage> = {
        // swiftlint:disable:next legacy_objc_type
        let cache = NSCache<NSString, NSImage>()
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
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func image(forKey key: String) -> NSImage? {
        // swiftlint:disable:next legacy_objc_type
        memory.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, forKey key: String) {
        // swiftlint:disable:next legacy_objc_type
        memory.setObject(image, forKey: key as NSString)
    }

    /// A box so the immutable, freshly decoded image can cross the actor boundary
    /// out of the detached downsample task under strict concurrency.
    struct DownsampledImage: @unchecked Sendable {
        let image: NSImage
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

        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height))
        return DownsampledImage(image: image)
    }
}
