//
//  NetworkConstraintMonitor.swift
//  coderpad
//

import Network
import Observation

/// Complements BuddyAppKit's reachability monitor with the active path's Low Data
/// Mode constraint, which must not be treated as fully offline (#3294).
///
/// `@MainActor` because the observable state is read from view bodies and written from
/// the path callback. Without it, `start()` could run off the main actor and race the
/// callbacks it installs, leaving two `NWPathMonitor`s running (#4571).
@MainActor
@Observable
final class NetworkConstraintMonitor {
    static let shared = NetworkConstraintMonitor()

    /// The path constraint as currently known. `unknown` until the first path arrives:
    /// starting out at "unconstrained" meant launch-time work could pick a policy for a
    /// connection nobody had looked at yet, and spend a metered allowance on it (#4573).
    enum ConstraintState: Equatable {
        case unknown
        case unconstrained
        case constrained
    }

    private(set) var state: ConstraintState = .unknown

    /// True only when the path is known to be constrained, so a banner never claims Low
    /// Data Mode before there is a path to judge.
    var isConstrained: Bool {
        state == .constrained
    }

    /// Whether a path has been observed at all. Work whose policy depends on the
    /// constraint should wait for this rather than reading `isConstrained` as "no".
    var hasResolvedPath: Bool {
        state != .unknown
    }

    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var queue: DispatchQueue?
    /// Invalidates callbacks from a monitor that has since been stopped or replaced, so a
    /// late update from a cancelled monitor cannot publish over a newer one.
    @ObservationIgnored private var generation = 0

    private init() {}

    /// Begins watching the default path's constraint. Idempotent: a second call keeps the
    /// running monitor.
    func start() {
        guard monitor == nil else { return }

        generation &+= 1
        let generation = generation
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.coderpad.app.network-constraint-monitor.\(generation)")
        self.monitor = monitor
        self.queue = queue
        monitor.pathUpdateHandler = { [weak self] path in
            let constrained = path.status == .satisfied && path.isConstrained
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, self.monitor != nil else { return }

                state = constrained ? .constrained : .unconstrained
            }
        }
        monitor.start(queue: queue)
    }

    /// Releases the path monitor and returns to the unknown state. Idempotent.
    ///
    /// A cancelled `NWPathMonitor` cannot be restarted, so `start()` builds a fresh one;
    /// bumping the generation first means any callback still in flight from the old
    /// monitor is discarded rather than publishing after the stop (#4572).
    func stop() {
        generation &+= 1
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        monitor = nil
        queue = nil
        state = .unknown
    }
}
