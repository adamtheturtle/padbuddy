//
//  LiveFilterPersistence.swift
//  coderpad
//
//  Coalesces the live-filter snapshot writes. `persistFilters()` fires on every
//  filter change, including each keystroke in the search field, and each one built a
//  full search value, JSON-encoded it, and wrote it to UserDefaults. The snapshot is
//  only ever read at launch (and by the restore on appear), so it does not need to be
//  current between keystrokes (#4783).
//
//  The same shape as `PreferenceCloudSync.scheduleMirror`, which coalesces its
//  defaults writes for the same reason.
//

import Foundation
import SwiftUI

/// Debounces per-key snapshot writes, keeping only the most recent one per key.
@MainActor
final class LiveFilterPersistence {
    static let shared: LiveFilterPersistence = {
        let persistence = LiveFilterPersistence()
        persistence.observers = flushNotifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak persistence] _ in
                // Delivered on the main queue, so we are already on the main actor.
                MainActor.assumeIsolated { persistence?.flushAll() }
            }
        }
        return persistence
    }()

    /// Long enough to absorb a burst of typing, short enough that leaving the pane or
    /// quitting within it still lands the write via `flush`.
    static let interval = Duration.milliseconds(400)

    private var pending: [String: Task<Void, Never>] = [:]
    private var writes: [String: @MainActor () -> Void] = [:]
    /// Held for the process's lifetime, as the store itself is; kept so the
    /// registration is explicit rather than discarded.
    private var observers: [any NSObjectProtocol] = []

    init() {}

    static func debounceKey(storageKey: String, scope: UUID) -> String {
        "\(storageKey).window.\(scope.uuidString)"
    }

    /// Termination and backgrounding, so a pending snapshot is not lost with the
    /// process. A dropped write would silently reopen the list with stale filters.
    private static var flushNotifications: [Notification.Name] {
        #if os(macOS)
            [NSApplication.willTerminateNotification, NSApplication.willResignActiveNotification]
        #elseif os(iOS) || os(visionOS)
            [UIApplication.willTerminateNotification, UIApplication.didEnterBackgroundNotification]
        #else
            []
        #endif
    }

    /// Replaces any snapshot already queued for `key`: only the newest matters, since
    /// each one is a complete replacement of the same stored value.
    func schedule(key: String, write: @escaping @MainActor () -> Void) {
        writes[key] = write
        pending[key]?.cancel()
        pending[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            self?.flush(key: key)
        }
    }

    /// Writes `key`'s queued snapshot immediately, if there is one. Called when a
    /// pane goes away, so leaving it does not lose the filters it was showing.
    func flush(key: String) {
        pending.removeValue(forKey: key)?.cancel()
        writes.removeValue(forKey: key)?()
    }

    func flushAll() {
        for key in Array(writes.keys) {
            flush(key: key)
        }
    }

    func cancelAll() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        writes.removeAll()
    }
}
