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
        private let initialContent: C

        init(content: C) {
            initialContent = content
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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
            // Matches SidebarToggleButton's fixed footprint, which is roomy enough
            // for the circular Liquid Glass container it adopts when collapsed.
            hosting.frame = NSRect(x: 0, y: 0, width: 44, height: 36)
            let controller = NSTitlebarAccessoryViewController()
            controller.view = hosting
            controller.layoutAttribute = .leading
            window.addTitlebarAccessoryViewController(controller)
            accessory = controller
            self.hosting = hosting
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
