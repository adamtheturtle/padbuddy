//
//  PlatformBridge.swift
//  coderpad
//
//  A single, small seam over the handful of AppKit/UIKit types that the otherwise
//  cross-platform code touches, so the multiplatform (macOS + iPad) target can share
//  one body of view/model code with minimal per-file `#if`. Mirrors the existing
//  `Clipboard`/`URLOpener`/`AppActivator` "thin seam" approach toward portability.
//
//  Naming follows the common `Platform*` convention: `PlatformImage`/`PlatformColor`
//  resolve to the native type per platform, and the small helpers below paper over
//  the few initializer/spelling differences (`Image(nsImage:)` vs `Image(uiImage:)`,
//  `NSImage(cgImage:size:)` vs `UIImage(cgImage:)`, screen scale).
//

import SwiftUI

#if os(macOS)
    import AppKit

    typealias PlatformImage = NSImage
    typealias PlatformColor = NSColor
    typealias PlatformFont = NSFont
#else
    import UIKit

    typealias PlatformImage = UIImage
    typealias PlatformColor = UIColor
    typealias PlatformFont = UIFont
#endif

extension PlatformFont {
    /// A monospaced system font of the given size/weight, spelled the same on both
    /// platforms (AppKit and UIKit share the `monospacedSystemFont(ofSize:weight:)`
    /// API but on different base classes).
    nonisolated static func monospaced(ofSize size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        monospacedSystemFont(ofSize: size, weight: weight)
    }
}

extension Color {
    /// Builds a SwiftUI `Color` from the platform's native colour type, hiding the
    /// `nsColor:`/`uiColor:` initializer-label difference from call sites. `nonisolated`
    /// so it can be called from nonisolated contexts (e.g. syntax highlighting's
    /// background attribute walk) under the project's MainActor-default isolation.
    nonisolated init(platformColor: PlatformColor) {
        #if os(macOS)
            self.init(nsColor: platformColor)
        #else
            self.init(uiColor: platformColor)
        #endif
    }
}

extension Image {
    /// Builds a SwiftUI `Image` from the platform's native image type, hiding the
    /// `nsImage:`/`uiImage:` initializer-label difference from call sites.
    nonisolated init(platformImage: PlatformImage) {
        #if os(macOS)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    /// Wraps a `CGImage` in the platform image type. AppKit needs an explicit point
    /// size (it has no inherent scale); UIKit derives size from the bitmap, so the
    /// size argument is only used on macOS.
    nonisolated static func fromCGImage(_ cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
            NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
            UIImage(cgImage: cgImage)
        #endif
    }
}

/// The main display's backing scale, used to size downsampled thumbnails. Both spellings
/// are deprecated-adjacent but remain the simplest non-view way to read a sensible scale;
/// a 2x fallback keeps callers honest when no screen is available.
enum PlatformScreen {
    @MainActor static var backingScaleFactor: CGFloat {
        #if os(macOS)
            NSScreen.main?.backingScaleFactor ?? 2
        #else
            UITraitCollection.current.displayScale
        #endif
    }
}
