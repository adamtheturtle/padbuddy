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
                String(localized: "Sending account to Apple Watch...")
            case .sent:
                String(localized: "Apple Watch connected. Open CoderPad on your watch to browse pads and questions.")
            case .queued:
                String(localized: "Account queued for Apple Watch. Open CoderPad on your watch to finish connecting.")
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
        @Published private(set) var statusAccountID: UUID?
        @Published private var activationState: WCSessionActivationState = .notActivated
        @Published private var isPaired = false
        @Published private var isWatchAppInstalled = false
        @Published private(set) var activationError: String?

        private let session: WCSession?

        override private init() {
            if WCSession.isSupported() {
                session = .default
            } else {
                session = nil
            }
            super.init()
            refreshAvailability()
            session?.delegate = self
            session?.activate()
        }

        var canProvision: Bool {
            activationState == .activated && isPaired && isWatchAppInstalled
        }

        func status(for accountID: UUID) -> WatchProvisioningStatus {
            companionStatusBelongsToAccount(statusAccountID: statusAccountID, accountID: accountID) ? status : .idle
        }

        var availabilityMessage: String? {
            guard session != nil else {
                return String(localized: "Apple Watch pairing is not available on this device.")
            }
            if let activationError { return activationError }
            guard activationState == .activated else { return String(localized: "Preparing Apple Watch connection...") }
            guard isPaired else { return String(localized: "Pair an Apple Watch with this iPhone first.") }
            guard isWatchAppInstalled else { return String(localized: "Install PadBuddy on Apple Watch first.") }

            return nil
        }

        private func refreshAvailability() {
            guard let session else {
                activationState = .notActivated
                isPaired = false
                isWatchAppInstalled = false
                invalidateStaleSuccess()
                return
            }

            activationState = session.activationState
            guard session.activationState == .activated else {
                isPaired = false
                isWatchAppInstalled = false
                invalidateStaleSuccess()
                return
            }

            isPaired = session.isPaired
            isWatchAppInstalled = session.isWatchAppInstalled
            invalidateStaleSuccess()
        }

        private func invalidateStaleSuccess() {
            guard companionSuccessIsStale(isSuccess: status == .sent, isAvailable: canProvision) else { return }
            status = .idle
            statusAccountID = nil
        }

        private var activationGuidance: String {
            String(localized: "Apple Watch connection is still starting. Try again in a moment.")
        }

        func retryActivation() {
            activationError = nil
            refreshAvailability()
            session?.activate()
        }

        private func replyFailureMessage(_ reply: [String: Any]) -> String {
            let replyError = (reply["errorCode"] as? String).flatMap(WatchProvisioningReplyError.init)
            return replyError == .invalidPayload
                ? String(localized: "The Apple Watch received an invalid account payload.")
                : String(localized: "The Apple Watch could not save this account.")
        }

        private func setStatus(_ newStatus: WatchProvisioningStatus, for accountID: UUID) {
            guard statusAccountID == accountID else { return }
            status = newStatus
        }

        func provision(account: Account) {
            let accountID = account.id
            statusAccountID = accountID
            guard let payload = TVProvisioningRequest.payload(for: account) else {
                status = .unavailable(String(localized: "This account cannot be sent to Apple Watch."))
                return
            }
            guard let session else {
                status = .unavailable(String(localized: "Apple Watch pairing is not available on this device."))
                return
            }
            guard session.activationState == .activated else {
                status = .unavailable(activationGuidance)
                session.activate()
                return
            }
            guard session.isPaired else {
                status = .unavailable(String(localized: "Pair an Apple Watch with this iPhone first."))
                return
            }
            guard session.isWatchAppInstalled else {
                status = .unavailable(String(localized: "Install PadBuddy on Apple Watch first."))
                return
            }

            status = .sending
            do {
                try session.updateApplicationContext(payload)
                session.transferUserInfo(payload)
            } catch {
                status = .failed(String(localized: """
                Could not prepare the Apple Watch connection: \(error.localizedDescription)
                """))
                return
            }

            guard session.isReachable else {
                status = .queued
                return
            }

            session.sendMessage(payload, replyHandler: { reply in
                Task { @MainActor in
                    if reply["ok"] as? Bool == true {
                        self.setStatus(.sent, for: accountID)
                    } else {
                        self.setStatus(.failed(self.replyFailureMessage(reply)), for: accountID)
                    }
                }
            }, errorHandler: { _ in
                Task { @MainActor in
                    self.setStatus(.queued, for: accountID)
                }
            })
        }
    }

    extension WatchProvisioningService: WCSessionDelegate {
        nonisolated func session(
            _: WCSession,
            activationDidCompleteWith state: WCSessionActivationState,
            error: (any Error)?
        ) {
            let failure = iPhoneWatchActivationFailure(
                isActivated: state == .activated,
                errorDescription: error?.localizedDescription
            )
            Task { @MainActor in
                self.activationError = failure
                self.refreshAvailability()
            }
        }

        nonisolated func sessionWatchStateDidChange(_: WCSession) {
            Task { @MainActor in
                self.refreshAvailability()
            }
        }

        nonisolated func sessionReachabilityDidChange(_: WCSession) {
            Task { @MainActor in
                self.refreshAvailability()
            }
        }

        nonisolated func sessionDidBecomeInactive(_: WCSession) {
            Task { @MainActor in
                self.refreshAvailability()
            }
        }

        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
            Task { @MainActor in
                self.activationError = nil
                self.refreshAvailability()
            }
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

        override private init() {
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
            replyHandler: ([String: Any]) -> Void
        ) {
            receive(message)
            replyHandler(["ok": true])
        }

        nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
            receive(message)
        }
    }
#endif
