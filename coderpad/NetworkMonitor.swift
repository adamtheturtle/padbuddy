//
//  NetworkMonitor.swift
//  coderpad
//
//  Observes system network reachability so the app can drop into a read-only mode
//  while there's no path to CoderPad. Reusing the same visual language as a revoked
//  key (a banner plus disabled editing controls), an offline app reads as "browse
//  only" rather than letting edits fail one failed request at a time (#321).
//

import Foundation
import Network

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True when the system reports no satisfied network path, so the app can't reach
    /// CoderPad and goes read-only. Defaults to `false` (online): a not-yet-started or
    /// just-launched monitor never falsely locks the UI before the first path update.
    private(set) var isOffline = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.adamdangoor.coderpad.network-monitor")
    @ObservationIgnored private var started = false

    private init() {}

    /// Begins watching the default network path. Idempotent: repeated calls keep the
    /// single existing monitor, mirroring the other launch-time monitors. Path updates
    /// arrive on a background queue, so the observable flag is set back on the main
    /// actor where the UI reads it.
    func start() {
        guard !started else { return }

        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                guard let self, self.isOffline != offline else { return }

                self.isOffline = offline
            }
        }
        monitor.start(queue: queue)
    }
}
