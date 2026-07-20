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

    let pipeline: ImagePipeline

    init(
        urlConfiguration: URLSessionConfiguration = WhiteboardImageCache.defaultURLConfiguration(),
        maxDownloadBytes: Int = WhiteboardImage.maxDownloadBytes
    ) {
        if urlConfiguration.urlCache == nil {
            urlConfiguration.urlCache = URLCache(
                memoryCapacity: 8 * 1024 * 1024,
                diskCapacity: 64 * 1024 * 1024,
                directory: nil
            )
        }
        urlConfiguration.requestCachePolicy = .useProtocolCachePolicy
        urlConfiguration.timeoutIntervalForRequest = 30
        urlConfiguration.timeoutIntervalForResource = 120

        let loader = DataLoader(configuration: urlConfiguration) { response in
            if let error = DataLoader.validate(response: response) { return error }
            guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
                return URLError(.cannotDecodeContentData)
            }

            return nil
        }

        let registry = ImageDecoderRegistry()
        var configuration = ImagePipeline.Configuration(dataLoader: loader)
        configuration.maximumResponseDataSize = maxDownloadBytes
        configuration.imageCache = ImageCache(costLimit: 64 * 1024 * 1024, countLimit: 32)
        configuration.makeImageDecoder = { context in
            registry.decoder(for: context).map(WhiteboardImageDecoder.init)
        }
        pipeline = ImagePipeline(configuration: configuration)
    }

    private nonisolated static func defaultURLConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            directory: nil
        )
        return configuration
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
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              width <= WhiteboardImageCache.maxSourcePixelsPerEdge,
              height <= WhiteboardImageCache.maxSourcePixelsPerEdge else {
            throw URLError(.cannotDecodeContentData)
        }

        var container = try base.decode(data)
        container.userInfo[.whiteboardIsAnimated] = CGImageSourceGetCount(source) > 1
        container.userInfo[.whiteboardStoredAt] = Date()
        return container
    }
}

private extension ImageContainer.UserInfoKey {
    nonisolated static let whiteboardIsAnimated: Self = "com.coderpad.whiteboard.is-animated"
    nonisolated static let whiteboardStoredAt: Self = "com.coderpad.whiteboard.stored-at"
}
