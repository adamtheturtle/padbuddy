//
//  WindowRepresentedURL.swift
//  coderpad
//

import SwiftUI

#if os(macOS)
    import AppKit

    struct WindowRepresentedURL: NSViewRepresentable {
        let url: URL?

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            apply(from: view, coordinator: context.coordinator)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            apply(from: nsView, coordinator: context.coordinator)
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            let appliedURL = coordinator.appliedURL
            DispatchQueue.main.async {
                guard let window = nsView.window, window.representedURL == appliedURL else { return }

                window.representedURL = nil
            }
        }

        private func apply(from view: NSView, coordinator: Coordinator) {
            let url = url
            DispatchQueue.main.async {
                guard let window = view.window else { return }

                coordinator.appliedURL = url
                if window.representedURL != url {
                    window.representedURL = url
                }
            }
        }

        final class Coordinator {
            var appliedURL: URL?
        }
    }

    extension View {
        func representedWindowURL(_ url: URL?) -> some View {
            background(WindowRepresentedURL(url: url))
        }
    }
#else
    extension View {
        func representedWindowURL(_: URL?) -> some View {
            self
        }
    }
#endif
