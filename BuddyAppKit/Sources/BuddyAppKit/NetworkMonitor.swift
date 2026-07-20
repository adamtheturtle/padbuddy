//
//  NetworkMonitor.swift
//  BuddyAppKit
//
//  Observes system network reachability so an app can drop into a read-only mode
//  while there's no path to its service. Reusing the same visual language as a
//  revoked key (a banner plus disabled editing controls), an offline app reads as
//  "browse only" rather than letting edits fail one failed request at a time (#321).
//

import Foundation
import Network

@Observable
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    /// True when the system reports no satisfied network path, so the app can't reach
    /// its service and goes read-only. Unknown initial/stopped state fails closed until
    /// a running monitor publishes a satisfied path, preventing premature mutations.
    public private(set) var isOffline = true

    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var queue: DispatchQueue?
    @ObservationIgnored private var generation = 0

    private init() {}

    /// Begins watching the default network path. Idempotent: repeated calls keep the
    /// single existing monitor, mirroring the other launch-time monitors. Path updates
    /// arrive on a background queue, so the observable flag is set back on the main
    /// actor where the UI reads it.
    public func start() {
        guard monitor == nil else { return }

        generation &+= 1
        let generation = generation
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.adamdangoor.buddyappkit.network-monitor.\(generation)")
        self.monitor = monitor
        self.queue = queue
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = Self.offlineState(pathIsSatisfied: path.status == .satisfied)
            Task { @MainActor in
                guard let self,
                      Self.isCurrentCallback(
                          generation, currentGeneration: self.generation, isRunning: self.monitor != nil
                      ), self.isOffline != offline else { return }

                self.isOffline = offline
            }
        }
        monitor.start(queue: queue)
    }

    /// Stops observation and releases the one-shot `NWPathMonitor`. A later `start`
    /// creates a fresh instance because canceled path monitors cannot be restarted.
    public func stop() {
        generation &+= 1
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        monitor = nil
        queue = nil
        isOffline = Self.offlineState(pathIsSatisfied: nil)
    }

    nonisolated static func offlineState(pathIsSatisfied: Bool?) -> Bool {
        pathIsSatisfied != true
    }

    nonisolated static func isCurrentCallback(
        _ generation: Int, currentGeneration: Int, isRunning: Bool
    ) -> Bool {
        isRunning && generation == currentGeneration
    }
}
