//
//  WhiteboardImage+Cache.swift
//  coderpad
//
//  The shared whiteboard thumbnail cache, split from WhiteboardImage.swift so both
//  files stay within the 400-line lint limit.
//

import CryptoKit
import ImageIO
import os
import SafeURLKit
import SwiftUI

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
        /// When this thumbnail was decoded, backing the revalidation-skip window
        /// (see `isFresh`).
        let storedAt: Date

        init(image: PlatformImage, isAnimated: Bool, storedAt: Date = Date()) {
            self.image = image
            self.isAnimated = isAnimated
            self.storedAt = storedAt
        }
    }

    /// How long a decoded thumbnail is trusted without revalidating (#2096). Long
    /// enough to cover flicking through a list of pads, short enough that an edit
    /// made behind an unchanged URL still shows up promptly (#792).
    nonisolated static let freshnessWindow: TimeInterval = 30

    /// Whether an entry decoded at `storedAt` is still inside `freshnessWindow`. A
    /// future `storedAt` (a clock moved backwards) reads as stale rather than fresh
    /// for the length of the jump, so a wall-clock change can't pin a stale drawing.
    nonisolated static func isFresh(storedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(storedAt)
        return age >= 0 && age < freshnessWindow
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
    nonisolated static func fetchBounded(
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
        // Appending one byte at a time cost millions of `Data.append` calls for a
        // body anywhere near the budget; buffer into a chunk and append that
        // instead (#2092). The running size check moves to the chunk boundary, so
        // an oversized body is still rejected mid-flight, just within one chunk of
        // the limit rather than at the exact byte.
        var chunk = [UInt8]()
        chunk.reserveCapacity(downloadChunkBytes)
        for try await byte in bytes {
            chunk.append(byte)
            guard chunk.count == downloadChunkBytes else { continue }

            data.append(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
            guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        }
        data.append(contentsOf: chunk)
        guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }

        return data
    }

    /// How much of a download to buffer before appending it to the accumulated
    /// body (#2092). Large enough that the per-append cost disappears, small
    /// enough that an oversized response is still caught long before it is fully
    /// in memory.
    private nonisolated static let downloadChunkBytes = 64 * 1024

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
