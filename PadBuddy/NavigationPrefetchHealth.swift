//
//  NavigationPrefetchHealth.swift
//  coderpad
//

import Foundation

@MainActor
enum NavigationPrefetchHealth {
    enum Kind: Hashable {
        case pads, questions, quota
    }

    private static var failures: [Kind: [UUID: String]] = [:]

    static func record(_ error: any Error, account: UUID, kind: Kind) {
        guard !Task.isCancelled, !(error is CancellationError),
              (error as? URLError)?.code != .cancelled else { return }

        if let clientError = error as? CoderPadError,
           case let .network(network) = clientError, network.code == .cancelled {
            return
        }

        failures[kind, default: [:]][account] = error.localizedDescription
    }

    static func clear(account: UUID, kind: Kind) {
        failures[kind]?[account] = nil
    }

    static func snapshot(kind: Kind) -> [UUID: String] {
        failures[kind] ?? [:]
    }
}
