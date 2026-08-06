#if os(macOS)
//
    //  MenuBarView+Failures.swift
    //  coderpad
//

    import Foundation

    extension MenuBarView {
        struct MenuLoadFailure: Equatable {
            let accountName: String
            let reason: String

            var displayText: String {
                "\(accountName): \(reason)"
            }
        }

        static func menuLoadFailureMessage(_ failures: [MenuLoadFailure]) -> String? {
            guard !failures.isEmpty else { return nil }

            let firstReason = failures[0].reason
            if failures.allSatisfy({ $0.reason == firstReason }) {
                if failures.count == 1 {
                    return failures[0].displayText
                }
                return String(localized: "^[\(failures.count) accounts](inflect: true): \(firstReason)")
            }

            return failures.map(\.displayText).joined(separator: "\n")
        }

        static func menuLoadFailureReason(for error: any Error) -> String {
            if let coderPadError = error as? CoderPadError, case let .network(urlError) = coderPadError {
                return menuNetworkFailureReason(for: urlError)
            }
            if let urlError = error as? URLError {
                return menuNetworkFailureReason(for: urlError)
            }
            return PadsBackgroundRefresher.failureLabel(PadsBackgroundRefresher.failureKind(for: error))
        }

        private static func menuNetworkFailureReason(for error: URLError) -> String {
            switch error.code {
            case .timedOut:
                PadsBackgroundRefresher.failureLabel(.timeout)
            default:
                PadsBackgroundRefresher.failureLabel(.network)
            }
        }
    }
#endif
