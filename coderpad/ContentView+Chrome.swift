//
//  ContentView+Chrome.swift
//  coderpad
//

import AppKit
import SwiftUI

/// The fixed sidebar toggle, centered on the traffic-light row via the titlebar
/// accessory. Same position whether the sidebar is shown or hidden.
struct SidebarToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        // Mail's behaviour: while the sidebar is expanded the toggle is a bare
        // glyph resting on the sidebar material. Once collapsed there's no sidebar
        // behind it, so it gains a circular Liquid Glass container (macOS 26) to
        // stay legible over the content pane. Leading-aligned in a fixed footprint
        // so it stays put next to the traffic lights as the style swaps.
        Group {
            if isCollapsed, #available(macOS 26, *) {
                // Apply the glass as a circular effect behind the *same* glyph used
                // when expanded, rather than `.buttonStyle(.glass)` — the glass
                // button imposes its own content metrics and shrinks the symbol.
                // This keeps the glyph at an identical 18pt across both states,
                // matching the section toolbar icons.
                Button(action: action) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: action) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 18, weight: .medium))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 36, alignment: .leading)
        .help("Toggle Sidebar")
        .accessibilityLabel("Toggle Sidebar")
    }
}

/// Hosts a SwiftUI control in the window's titlebar, pinned to the leading edge
/// just right of the traffic lights and vertically centered on that row. Living
/// in the titlebar rather than a split column keeps it fixed when the sidebar
/// collapses or expands — and AppKit handles the alignment for us.
struct TitlebarLeadingAccessory<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: Content

    func makeNSView(context _: Context) -> NSView {
        AccessoryAnchor(content: content)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? AccessoryAnchor<Content>)?.update(content: content)
    }

    final class AccessoryAnchor<C: View>: NSView {
        private var accessory: NSTitlebarAccessoryViewController?
        private var hosting: NSHostingView<C>?
        private var container: NSView?
        private let initialContent: C

        /// SidebarToggleButton's fixed footprint, roomy enough for the circular
        /// Liquid Glass container it adopts when collapsed.
        private static var glyphSize: NSSize { NSSize(width: 44, height: 36) }

        /// Leading inset applied to the toggle while full screen. Windowed, the
        /// traffic lights push the accessory inward; full screen has none, so a
        /// flush-left glyph reads as a layout bug. This margin restores a
        /// deliberate gap from the screen edge.
        private static var fullScreenInset: CGFloat { 13 }

        init(content: C) {
            initialContent = content
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, accessory == nil else { return }
            // `viewDidMoveToWindow` fires while SwiftUI is still installing this
            // hosting subtree — i.e. mid-layout. Adding a titlebar accessory forces
            // the window's title bar to re-lay-out immediately, which AppKit reports
            // as layout recursion ("-layoutSubtreeIfNeeded on a view which is already
            // being laid out"). Defer the install one runloop tick so it lands after
            // the current layout pass completes.
            DispatchQueue.main.async { [weak self] in
                self?.installAccessory()
            }
        }

        private func installAccessory() {
            guard let window, accessory == nil else { return }
            let hosting = NSHostingView(rootView: initialContent)
            // Wrap the glyph in a container so its leading inset can grow in full
            // screen without disturbing the SwiftUI content itself.
            let container = NSView(frame: NSRect(origin: .zero, size: Self.glyphSize))
            container.autoresizesSubviews = true
            // AppKit sizes the accessory host to the full (tall, macOS 26) titlebar
            // height but leaves this container at its own frame height unless we let
            // it grow. Flex the height so the container fills the titlebar; the
            // hosting view's `[.minYMargin, .maxYMargin]` mask then centers the glyph
            // on the traffic-light row instead of pinning it to the top.
            container.autoresizingMask = [.height]
            hosting.frame = NSRect(origin: .zero, size: Self.glyphSize)
            // AppKit stretches a leading accessory's view to the full title-bar
            // height. Keep the glyph pinned to the leading edge but vertically
            // centered as that height grows, rather than sinking to the bottom.
            hosting.autoresizingMask = [.maxXMargin, .minYMargin, .maxYMargin]
            container.addSubview(hosting)
            let controller = NSTitlebarAccessoryViewController()
            controller.view = container
            controller.layoutAttribute = .leading
            window.addTitlebarAccessoryViewController(controller)
            accessory = controller
            self.hosting = hosting
            self.container = container

            let center = NotificationCenter.default
            for name: NSNotification.Name in [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ] {
                center.addObserver(self, selector: #selector(layoutForFullScreen), name: name, object: window)
            }
            layoutForFullScreen()
        }

        /// Offsets the glyph by ``fullScreenInset`` while full screen and widens the
        /// container to match, so the toggle keeps a margin from the screen edge in
        /// the absence of the traffic lights.
        @objc private func layoutForFullScreen() {
            guard let container, let hosting else { return }
            let inset = (window?.styleMask.contains(.fullScreen) ?? false) ? Self.fullScreenInset : 0
            // Adjust only the width AppKit lets us own; its auto-set title-bar
            // height and the glyph's centering autoresizing mask handle the rest.
            var frame = container.frame
            frame.size.width = Self.glyphSize.width + inset
            container.frame = frame
            hosting.frame.origin.x = inset
        }

        func update(content: C) {
            hosting?.rootView = content
        }
    }
}

struct UnauthorizedBanner: View {
    let monitor: AccountHealthMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This API key was rejected by CoderPad")
                    .font(.callout.weight(.semibold))
                Text("Open Settings and update or replace the key for this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                let navigation = SettingsNavigation.shared
                navigation.selectedTab = .accounts
                navigation.accountToEdit = AccountsStore.shared.currentAccountID
                openSettings()
            }
            .controlSize(.small)
            Button("Recheck") {
                Task { await monitor.checkCurrentAccount() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.bannerH)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
    }
}
