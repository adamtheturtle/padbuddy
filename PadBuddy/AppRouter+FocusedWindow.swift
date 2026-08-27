//
//  AppRouter+FocusedWindow.swift
//  coderpad
//
//  Scoping a process-wide router broadcast to the focused window.
//

import Foundation
import os
import SwiftUI

/// Consumes an `AppRouter` broadcast only while this view's window is focused.
/// The router's commands are process-wide notifications, so without this every
/// window acted on them at once: ⌘R reloaded every mounted list in every window
/// (#905), and Open Pad by URL / the command palette presented their UI in every
/// main window simultaneously (#906). The focused-window state is tracked through
/// a reference box because the long-running consumption task would otherwise
/// capture a stale `controlActiveState` snapshot from one body evaluation.
/// `controlActiveState` doesn't exist on iOS, where `scenePhase` gives the same
/// signal: only the scene the user is in reports `.active` (#2685).
@MainActor
final class RouterWindowFocus {
    /// An unmounted window has not established focus and must not consume a
    /// process-wide request before its environment is sampled (#2062).
    var isFocused = false
}

private struct FocusedWindowRequestModifier: ViewModifier {
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #else
        @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var focus = RouterWindowFocus()
    let kind: FocusedWindowRequestKind
    let stream: () -> AsyncStream<Void>
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        focusTracking(content)
        #if os(macOS)
            .onAppear { updateFocus(controlActiveState != .inactive) }
            .onChange(of: controlActiveState) { _, state in updateFocus(state != .inactive) }
        #else
            // `controlActiveState` is macOS-only, so every iOS scene used to count as
            // focused — and in iPad multi-window a reload or palette request was then
            // handled by all of them at once (#2685). `scenePhase` is the equivalent
            // signal: only the scene the user is in reports `.active`.
            .onAppear { updateFocus(scenePhase == .active) }
            .onChange(of: scenePhase) { _, phase in updateFocus(phase == .active) }
        #endif
    }

    private func focusTracking(_ content: Content) -> some View {
        content.task { [focus] in
            for await _ in stream() {
                guard AppRouter.claimFocusedRequest(kind, isFocused: focus.isFocused) else { continue }

                await action()
            }
        }
    }

    private func updateFocus(_ isFocused: Bool) {
        focus.isFocused = isFocused
        guard AppRouter.claimFocusedRequest(kind, isFocused: isFocused) else { return }

        Task { await action() }
    }
}

extension View {
    /// Runs `action` for an `AppRouter` void broadcast, but only while this view's
    /// window is the focused one (#905, #906).
    func onFocusedWindowRequest(_ kind: FocusedWindowRequestKind,
                                _ stream: @escaping () -> AsyncStream<Void>,
                                perform action: @escaping @MainActor () async -> Void) -> some View {
        modifier(FocusedWindowRequestModifier(kind: kind, stream: stream, action: action))
    }

    /// Reload-on-⌘R scoped to the focused window (#905).
    func onReloadRequest(perform action: @escaping @MainActor () async -> Void) -> some View {
        onFocusedWindowRequest(.reload, { AppRouter.reloads }, perform: action)
    }
}
