//
//  WindowRequestConsumer.swift
//  coderpad
//
//  Focus-gated consumption for the durable AppNavigation request mailbox.
//
//  The mailbox requests (section switches, list filters, pad/question commands)
//  are process-wide, and every mounted view used to observe them directly - so
//  with several main windows open, whichever view's observer fired first
//  consumed the request. A background window could steal a menu command, a
//  sidebar filter, or a favorite selection aimed at the focused one (#907,
//  #910, #871, #869). Routing every consumption through this modifier means
//  only the focused window's views consume; requests queued while the app is
//  in the background survive until a window becomes focused.
//

import SwiftUI

private struct WindowRequestConsumer<Value: Equatable>: ViewModifier {
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #endif
    let value: Value?
    let consume: @MainActor () -> Void

    /// iOS has no `controlActiveState`; every scene attempts there (the
    /// pre-existing behavior), and the consume closures' own id/guard checks
    /// keep that safe - the first matching scene clears the request.
    private var isFocusedWindow: Bool {
        #if os(macOS)
            controlActiveState != .inactive
        #else
            true
        #endif
    }

    func body(content: Content) -> some View {
        #if os(macOS)
            observing(content)
                // A request queued while this window was in the background (or
                // while a different window was focused and didn't match it) is
                // retried the moment focus lands here.
                .onChange(of: controlActiveState) { _, _ in attempt() }
        #else
            observing(content)
        #endif
    }

    private func observing(_ content: Content) -> some View {
        content
            .onAppear { attempt() }
            .onChange(of: value) { _, _ in attempt() }
    }

    private func attempt() {
        guard isFocusedWindow, value != nil else { return }

        // Deferred one runloop: attempts fire from `onAppear`/`onChange`, where
        // consuming (which mutates observable navigation state) mid-update
        // risks the "modifying state during view update" hazard. The consume
        // closures re-check the request themselves, so a stale attempt no-ops.
        DispatchQueue.main.async { consume() }
    }
}

extension View {
    /// Consumes a durable `AppNavigation` request only while this view's window
    /// is the focused one: on appear, whenever the request value changes, and
    /// when focus arrives with a request still pending. `consume` must re-check
    /// and clear the request itself (all the mailbox consumers already do).
    func consumesWindowRequest(
        _ value: (some Equatable)?,
        perform consume: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(WindowRequestConsumer(value: value, consume: consume))
    }
}
