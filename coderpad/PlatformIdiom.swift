//
//  PlatformIdiom.swift
//  coderpad
//

import SwiftUI
#if !os(macOS)
    import UIKit
#endif

enum PlatformIdiom {
    @MainActor
    static var usesVisionInterface: Bool {
        #if os(visionOS)
            true
        #elseif !os(macOS)
            if #available(iOS 17.0, *) {
                UIDevice.current.userInterfaceIdiom == .vision
            } else {
                false
            }
        #else
            false
        #endif
    }
}
