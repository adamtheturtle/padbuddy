//
//  WindowScope.swift
//  coderpad
//
//  A per-window identity token.
//

import SwiftUI

/// Identifies the window a view is being rendered in.
///
/// SwiftUI offers no built-in per-window token, so state that ought to be
/// per-window ends up in process-global singletons keyed by account and item —
/// where a second window on the same pad or question silently shares, and
/// overwrites, the first window's value. Views that must not do that mix this
/// into their key.
///
/// A scope is minted by `windowScoped()` at each scene's root. Because it lives
/// in that root view's `@State`, it is created once and stays stable for the
/// life of the window, while a second window's root mints its own.
struct WindowScope: Hashable {
    let id: UUID

    init() {
        id = UUID()
    }

    private init(id: UUID) {
        self.id = id
    }

    /// The scope a view gets when nothing has called `windowScoped()` above it —
    /// previews, render tests, and any host that doesn't model windows. Shared
    /// on purpose: without real windows there is nothing to keep apart, and a
    /// fixed value keeps such keys stable across mounts.
    static let unscoped = Self(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))

    /// A short token for embedding in a storage key.
    var token: String {
        id.uuidString
    }
}

extension EnvironmentValues {
    /// The window this view is rendered in. See `WindowScope`.
    @Entry var windowScope: WindowScope = .unscoped
}

/// Mints one `WindowScope` and publishes it to everything below. Apply at the
/// root of every scene's content — nesting it would split one window into two
/// scopes and defeat the point.
private struct WindowScopeRoot: ViewModifier {
    @State private var scope = WindowScope()

    func body(content: Content) -> some View {
        content
            .environment(\.windowScope, scope)
            // Every scene root passes through here, which makes it the one place that
            // knows the app has something on screen — the signal App Intents wait on
            // instead of a fixed warm-up sleep (#2356).
            .onAppear { AppReadiness.markReady() }
    }
}

extension View {
    /// Marks this view as a window's root, giving it and its descendants a
    /// window-unique `windowScope`.
    func windowScoped() -> some View {
        modifier(WindowScopeRoot())
    }
}
