#if os(iOS)
    import Combine
    import Foundation
    @preconcurrency import WatchConnectivity

    enum WatchProvisioningStatus: Equatable {
        case idle
        case sending
        case sent
        case queued
        case unavailable(String)
        case failed(String)

        var message: String? {
            switch self {
            case .idle:
                nil
            case .sending:
                "Sending account to Apple Watch..."
            case .sent:
                "Apple Watch connected. Open CoderPad on your watch to browse pads and questions."
            case .queued:
                "Account queued for Apple Watch. Open CoderPad on your watch to finish connecting."
            case let .unavailable(reason), let .failed(reason):
                reason
            }
        }

        var systemImage: String {
            switch self {
            case .idle, .sending:
                "applewatch"
            case .sent:
                "checkmark.circle.fill"
            case .queued:
                "clock.fill"
            case .unavailable, .failed:
                "exclamationmark.triangle.fill"
            }
        }
    }

    @MainActor
    final class WatchProvisioningService: NSObject, ObservableObject {
        static let shared = WatchProvisioningService()

        @Published private(set) var status: WatchProvisioningStatus = .idle

        private let session: WCSession?

        private override init() {
            if WCSession.isSupported() {
                session = .default
            } else {
                session = nil
            }
            super.init()
            session?.delegate = self
            session?.activate()
        }

        var canProvision: Bool {
            guard let session, session.activationState == .activated else { return false }
            return session.isPaired && session.isWatchAppInstalled
        }

        var availabilityMessage: String? {
            guard let session else { return "Apple Watch pairing is not available on this device." }
            guard session.activationState == .activated else { return "Preparing Apple Watch connection..." }
            guard session.isPaired else { return "Pair an Apple Watch with this iPhone first." }
            guard session.isWatchAppInstalled else { return "Install CoderPad on Apple Watch first." }
            return nil
        }

        func provision(account: Account) {
            guard let payload = TVProvisioningRequest.payload(for: account) else {
                status = .unavailable("This account cannot be sent to Apple Watch.")
                return
            }
            guard let session else {
                status = .unavailable("Apple Watch pairing is not available on this device.")
                return
            }
            guard session.activationState == .activated else {
                status = .unavailable("Apple Watch connection is still starting. Try again in a moment.")
                session.activate()
                return
            }
            guard session.isPaired else {
                status = .unavailable("Pair an Apple Watch with this iPhone first.")
                return
            }
            guard session.isWatchAppInstalled else {
                status = .unavailable("Install CoderPad on Apple Watch first.")
                return
            }

            status = .sending
            do {
                try session.updateApplicationContext(payload)
                session.transferUserInfo(payload)
            } catch {
                status = .failed("Could not prepare the Apple Watch connection: \(error.localizedDescription)")
                return
            }

            guard session.isReachable else {
                status = .queued
                return
            }

            session.sendMessage(payload, replyHandler: { _ in
                Task { @MainActor in
                    self.status = .sent
                }
            }, errorHandler: { _ in
                Task { @MainActor in
                    self.status = .queued
                }
            })
        }
    }

    extension WatchProvisioningService: WCSessionDelegate {
        nonisolated func session(
            _: WCSession,
            activationDidCompleteWith _: WCSessionActivationState,
            error _: (any Error)?
        ) {}

        nonisolated func sessionDidBecomeInactive(_: WCSession) {}

        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    }
#endif

#if os(watchOS)
    import Foundation
    @preconcurrency import WatchConnectivity

    @MainActor
    final class WatchProvisioningReceiver: NSObject {
        static let shared = WatchProvisioningReceiver()

        private var session: WCSession?
        private var provision: (([String: Any]) -> Void)?

        private override init() {
            super.init()
        }

        func activate(provision: @escaping ([String: Any]) -> Void) {
            self.provision = provision
            guard WCSession.isSupported() else { return }

            let session = WCSession.default
            self.session = session
            session.delegate = self
            session.activate()

            if !session.receivedApplicationContext.isEmpty {
                provision(session.receivedApplicationContext)
            }
        }

        private func receive(_ payload: [String: Any]) {
            Task { @MainActor in
                self.provision?(payload)
            }
        }
    }

    extension WatchProvisioningReceiver: WCSessionDelegate {
        nonisolated func session(
            _: WCSession,
            activationDidCompleteWith _: WCSessionActivationState,
            error _: (any Error)?
        ) {}

        nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            receive(applicationContext)
        }

        nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
            receive(userInfo)
        }

        nonisolated func session(
            _: WCSession,
            didReceiveMessage message: [String: Any],
            replyHandler: @escaping ([String: Any]) -> Void
        ) {
            receive(message)
            replyHandler(["ok": true])
        }

        nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
            receive(message)
        }
    }
#endif
