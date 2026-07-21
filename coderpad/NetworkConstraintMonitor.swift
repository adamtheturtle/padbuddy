//
//  NetworkConstraintMonitor.swift
//  coderpad
//

import Network
import Observation

/// Complements BuddyAppKit's reachability monitor with the active path's Low Data
/// Mode constraint, which must not be treated as fully offline (#3294).
@Observable
final class NetworkConstraintMonitor {
    static let shared = NetworkConstraintMonitor()

    private(set) var isConstrained = false
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var queue: DispatchQueue?

    private init() {}

    func start() {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.coderpad.app.network-constraint-monitor")
        self.monitor = monitor
        self.queue = queue
        monitor.pathUpdateHandler = { [weak self] path in
            let constrained = path.status == .satisfied && path.isConstrained
            Task { @MainActor [weak self] in
                guard self?.monitor === monitor else { return }

                self?.isConstrained = constrained
            }
        }
        monitor.start(queue: queue)
    }
}
