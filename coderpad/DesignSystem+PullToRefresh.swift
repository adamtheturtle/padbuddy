//
//  DesignSystem+PullToRefresh.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

// MARK: - Pull to refresh (macOS)

extension View {
    /// Adds a pull-to-refresh gesture to a scrollable container such as `List`.
    ///
    /// SwiftUI's `.refreshable` compiles on macOS but never fires from a gesture —
    /// AppKit has no system pull-to-refresh control. This bridges to the
    /// `NSScrollView` underneath the SwiftUI container: it tracks how far the
    /// content rubber-bands past its top edge and, when the user releases beyond a
    /// threshold, runs `action`. A circular indicator fades in as the user pulls
    /// and spins while the refresh is in flight.
    ///
    /// iOS: this whole bridge exists only to make up for AppKit lacking a system
    /// pull-to-refresh. UIKit/SwiftUI on iOS have a native one, so call sites should
    /// use `.refreshable` directly there; this modifier is a no-op so they still
    /// compile if they apply it unconditionally.
    func macPullToRefresh(_ action: @escaping () async -> Void) -> some View {
        #if os(macOS)
            return modifier(MacPullToRefresh(action: action))
        #else
            _ = action
            return self
        #endif
    }
}

#if os(macOS)

private struct MacPullToRefresh: ViewModifier {
    let action: () async -> Void

    /// How far (in points) the content must be dragged past the top before
    /// releasing triggers a refresh. Kept low so a short trackpad pull is enough.
    private let threshold: CGFloat = 24

    /// 0…1 as the user drags past the top; drives the indicator's reveal.
    @State private var pull: CGFloat = 0
    @State private var isRefreshing = false
    /// The indicator chevron's point size, scaled with the user's preferred text
    /// size (tracking Caption 2) so it honors the accessibility setting.
    @ScaledMetric(relativeTo: .caption2) private var chevronSize: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                PullToRefreshScrollBridge(threshold: threshold, pull: $pull) {
                    guard !isRefreshing else { return }

                    isRefreshing = true
                    Task {
                        await action()
                        isRefreshing = false
                    }
                }
            )
            .overlay(alignment: .top) { indicator }
    }

    /// Whether the user has pulled far enough that releasing will refresh.
    private var isArmed: Bool {
        pull >= 1
    }

    @ViewBuilder
    private var indicator: some View {
        if isRefreshing || pull > 0 {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    // A ring that fills as the content is dragged toward the
                    // threshold, with a chevron that flips up once armed to
                    // signal "release to refresh".
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: pull)
                            .stroke(Color.accentColor,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "chevron.down")
                            .font(.system(size: chevronSize, weight: .bold))
                            .foregroundStyle(isArmed ? Color.accentColor : Color.secondary)
                            .rotationEffect(.degrees(isArmed ? 180 : 0))
                    }
                    .frame(width: 16, height: 16)
                }
            }
            .padding(7)
            // A floating indicator above the scrolling list, so it gets Liquid
            // Glass to refract the content sliding under it on macOS 26, keeping
            // the opaque material as the macOS 15 fallback.
            .floatingGlass(in: Circle(), fallback: .regularMaterial)
            .overlay(Circle().stroke(Color.subtleStroke, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .scaleEffect(isRefreshing ? 1 : max(0.6, pull))
            .opacity(isRefreshing ? 1 : Double(min(1, pull * 1.4)))
            .padding(.top, 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRefreshing)
            .animation(.easeOut(duration: 0.12), value: isArmed)
            .allowsHitTesting(false)
        }
    }
}

/// Locates the `NSScrollView` backing the SwiftUI container it is placed behind
/// and reports over-scroll past the top edge back to SwiftUI.
private struct PullToRefreshScrollBridge: NSViewRepresentable {
    let threshold: CGFloat
    @Binding var pull: CGFloat
    let onTrigger: () -> Void

    func makeNSView(context: Context) -> ScrollFinderView {
        let view = ScrollFinderView()
        let coordinator = context.coordinator
        // The enclosing scroll view doesn't exist yet at make time, so connect
        // once this helper view is committed into the window hierarchy.
        view.onMoveToWindow = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return }

            coordinator.connect(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: ScrollFinderView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.pull = $pull
        context.coordinator.onTrigger = onTrigger
        // Retry in case the scroll view wasn't reachable at first window attach.
        context.coordinator.connect(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// An otherwise-invisible helper that fires `onMoveToWindow` once it lands in
    /// the window, giving the coordinator a moment when sibling AppKit views exist.
    final class ScrollFinderView: NSView {
        var onMoveToWindow: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onMoveToWindow?() }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var threshold: CGFloat = 80
        var pull: Binding<CGFloat>?
        var onTrigger: () -> Void = {}

        private weak var scrollView: NSScrollView?
        private var overscroll: CGFloat = 0
        /// True only between `willStartLiveScroll` and `didEndLiveScroll`, i.e. while
        /// the user is actively scrolling. Bounds changes also fire during launch and
        /// programmatic layout, when the flipped clip view's origin can briefly dip
        /// negative as the list settles — gating the pull on a live scroll keeps the
        /// indicator from appearing on its own at launch (#360).
        private var isLiveScrolling = false

        func connect(from view: NSView) {
            guard scrollView == nil, let scrollView = Self.scrollView(near: view) else { return }

            self.scrollView = scrollView
            // Guarantee rubber-banding at the top even when the list is short.
            scrollView.verticalScrollElasticity = .allowed
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(boundsChanged),
                               name: NSView.boundsDidChangeNotification, object: clip)
            center.addObserver(self, selector: #selector(liveScrollStarted),
                               name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
            center.addObserver(self, selector: #selector(liveScrollEnded),
                               name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }

        @objc private func liveScrollStarted() {
            isLiveScrolling = true
            overscroll = 0
        }

        @objc private func boundsChanged() {
            // Ignore bounds changes that aren't part of a user scroll (launch, list
            // reloads, programmatic layout) so the indicator only reveals on a pull.
            guard isLiveScrolling, let scrollView else { return }

            // A `List` uses a flipped clip view, so the visible origin dips below
            // zero as the content rubber-bands past the top edge.
            overscroll = max(0, -scrollView.contentView.bounds.origin.y)
            // This AppKit notification can fire while SwiftUI is mid-layout (e.g. when
            // the list reloads), so defer the @State write to the next runloop tick to
            // avoid "modifying state during view update". `overscroll` stays in sync
            // synchronously, so the release trigger below remains accurate.
            let newPull = min(1, overscroll / threshold)
            DispatchQueue.main.async { [weak self] in
                self?.pull?.wrappedValue = newPull
            }
        }

        @objc private func liveScrollEnded() {
            isLiveScrolling = false
            let shouldTrigger = overscroll >= threshold
            overscroll = 0
            DispatchQueue.main.async { [weak self] in
                self?.pull?.wrappedValue = 0
                if shouldTrigger { self?.onTrigger() }
            }
        }

        /// Finds the scroll view this helper is layered over. A `ScrollView`'s
        /// `.background` lands *inside* its scroll view, so the enclosing one is
        /// correct. A `List` instead places the background outside its scroll
        /// view, so fall back to the smallest scroll view in the window whose
        /// frame sits under the helper — i.e. the one it fronts, not a
        /// neighbouring pane's, which a naive descendant search can pick by
        /// mistake.
        private static func scrollView(near view: NSView) -> NSScrollView? {
            if let enclosing = view.enclosingScrollView { return enclosing }
            guard let root = view.window?.contentView else { return nil }

            let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: root)
            var best: NSScrollView?
            var bestArea = CGFloat.greatestFiniteMagnitude
            func walk(_ node: NSView) {
                if let scroll = node as? NSScrollView {
                    let frame = scroll.convert(scroll.bounds, to: root)
                    if frame.contains(point) {
                        let area = frame.width * frame.height
                        if area < bestArea {
                            best = scroll
                            bestArea = area
                        }
                    }
                }
                node.subviews.forEach(walk)
            }
            walk(root)
            return best
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
#endif
