//
//  WhiteboardImageCache.swift
//  coderpad
//
//  Nuke-backed loading for the pad whiteboard thumbnail. The shared pipeline
//  owns networking, HTTP caching, request coalescing, cancellation, thumbnail
//  decoding, and the decoded-image LRU; this file retains only app policy.
//

import CryptoKit
import Foundation
import ImageIO
import Nuke
import os
import SafeURLKit

@MainActor
final class WhiteboardImageCache {
    static let shared = WhiteboardImageCache()
    nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "whiteboard")

    struct Entry {
        let image: PlatformImage
        let isAnimated: Bool
        let storedAt: Date
    }

    nonisolated static let freshnessWindow: TimeInterval = 30
    nonisolated static let maxSourcePixelsPerEdge = 20000
    /// Checking each edge alone still admitted 20,000 x 20,000 — 400 million pixels, or
    /// roughly 1.6 GB decoded — from a well-compressed response inside the 20 MB download
    /// cap (#4603). The area cap is what actually bounds the decode.
    nonisolated static let maxSourcePixels = 40_000_000
    /// Animated formats multiply the work by their frame count, so that is bounded too.
    nonisolated static let maxSourceFrames = 300
    nonisolated static let maxAggregateSourcePixels = 40_000_000

    /// Whether a source's metadata describes an image worth decoding. Deliberately
    /// evaluated from `CGImageSourceCopyProperties` before any decode, so an oversized
    /// image costs a header read rather than the allocation it was asking for.
    nonisolated static func allowsSource(width: Int, height: Int, frames: Int) -> Bool {
        guard width > 0, height > 0, frames > 0,
              width <= maxSourcePixelsPerEdge, height <= maxSourcePixelsPerEdge,
              frames <= maxSourceFrames else { return false }

        let (pixels, overflowed) = width.multipliedReportingOverflow(by: height)
        guard !overflowed, pixels <= maxSourcePixels else { return false }

        let (aggregatePixels, aggregateOverflowed) = pixels.multipliedReportingOverflow(by: frames)
        return !aggregateOverflowed && aggregatePixels <= maxAggregateSourcePixels
    }

    let pipeline: ImagePipeline
    private let urlCache: URLCache?

    init(
        urlConfiguration: URLSessionConfiguration = WhiteboardImageCache.defaultURLConfiguration(),
        maxDownloadBytes: Int = WhiteboardImage.maxDownloadBytes
    ) {
        if urlConfiguration.urlCache == nil {
            urlConfiguration.urlCache = Self.memoryOnlyURLCache()
        }
        urlConfiguration.requestCachePolicy = .useProtocolCachePolicy
        urlConfiguration.timeoutIntervalForRequest = 30
        urlConfiguration.timeoutIntervalForResource = 120
        urlCache = urlConfiguration.urlCache

        let redirectPolicy = PolicyEnforcingRedirectDelegate(policy: WhiteboardImage.imageURLPolicy)
        let loader = DataLoader(configuration: urlConfiguration) { response in
            if let error = DataLoader.validate(response: response) {
                return error
            }
            // A refused redirect surfaces as the 3xx itself rather than an error, so the
            // load must not treat that as a usable response.
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return URLError(.badServerResponse)
            }
            guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
                return URLError(.cannotDecodeContentData)
            }

            return nil
        }

        // `isAllowedImageURL` checks only the URL the app was given. URLSession follows
        // redirects on its own, so without this an allowed public HTTPS URL could redirect
        // to loopback, link-local, or a LAN address (#4599), or downgrade to plaintext
        // (#4600) — with the destination never seeing the policy at all.
        loader.delegate = redirectPolicy

        let registry = ImageDecoderRegistry()
        var configuration = ImagePipeline.Configuration(dataLoader: loader)
        configuration.maximumResponseDataSize = maxDownloadBytes
        configuration.imageCache = ImageCache(costLimit: 64 * 1024 * 1024, countLimit: 32)
        configuration.makeImageDecoder = { context in
            registry.decoder(for: context).map(WhiteboardImageDecoder.init)
        }
        pipeline = ImagePipeline(configuration: configuration)
    }

    func clear() {
        pipeline.cache.removeAll()
        urlCache?.removeAllCachedResponses()
    }

    private nonisolated static func defaultURLConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = memoryOnlyURLCache()
        return configuration
    }

    /// Memory-only, deliberately. `URLCache` keys entries on the request URL and writes
    /// them to disk verbatim, and whiteboard export URLs carry their signature in the
    /// query — so a disk cache persisted signed URLs, and the candidate's drawing
    /// alongside them, well past the session that fetched them (#4601). The cost is
    /// re-fetching a thumbnail after a relaunch.
    private nonisolated static func memoryOnlyURLCache() -> URLCache {
        URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0, directory: nil)
    }

    nonisolated static func isFresh(storedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(storedAt)
        return age >= 0 && age < freshnessWindow
    }

    nonisolated static func request(url: URL, maxPixelSize: Int, revalidating: Bool = false) -> ImageRequest {
        var request = ImageRequest(url: url)
        request.imageID = cacheKey(url: url)
        request.thumbnail = .init(maxPixelSize: Float(maxPixelSize))
        if revalidating {
            // Skip Nuke's decoded cache while retaining URLSession's protocol cache,
            // which performs a conditional request when validators are available.
            request.options.insert(.disableMemoryCacheReads)
        }
        return request
    }

    /// Keep signed/token-bearing URLs out of Nuke's longer-lived in-memory keys.
    nonisolated static func cacheKey(url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated func image(for request: ImageRequest) -> Entry? {
        pipeline.cache.cachedImage(for: request, caches: .memory).map(Self.entry)
    }

    nonisolated func load(_ request: ImageRequest) async throws -> Entry {
        let response = try await pipeline.imageTask(with: request).response
        return Self.entry(response.container)
    }

    private nonisolated static func entry(_ container: ImageContainer) -> Entry {
        Entry(
            image: container.image,
            isAnimated: container.userInfo[.whiteboardIsAnimated] as? Bool ?? false,
            storedAt: container.userInfo[.whiteboardStoredAt] as? Date ?? .distantPast
        )
    }
}

private struct WhiteboardImageDecoder: ImageDecoding {
    let base: any ImageDecoding

    var isAsynchronous: Bool {
        base.isAsynchronous
    }

    func decode(_ data: Data) throws -> ImageContainer {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw URLError(.cannotDecodeContentData)
        }

        // Every bound is checked from metadata, before `base.decode` allocates anything.
        let frames = CGImageSourceGetCount(source)
        guard WhiteboardImageCache.allowsSource(width: width, height: height, frames: frames) else {
            throw URLError(.cannotDecodeContentData)
        }

        var container = try base.decode(data)
        container.userInfo[.whiteboardIsAnimated] = frames > 1
        container.userInfo[.whiteboardStoredAt] = Date()
        return container
    }
}

private extension ImageContainer.UserInfoKey {
    nonisolated static let whiteboardIsAnimated: Self = "com.coderpad.whiteboard.is-animated"
    nonisolated static let whiteboardStoredAt: Self = "com.coderpad.whiteboard.stored-at"
}
