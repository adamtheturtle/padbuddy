// swiftlint:disable file_length
#if os(watchOS)
    import Combine
    import Security
    import SwiftUI
    @preconcurrency import WatchConnectivity

    @main
    struct CoderpadWatchApp: App {
        @StateObject private var session = WatchSession()

        var body: some Scene {
            WindowGroup {
                WatchRootView()
                    .environmentObject(session)
            }
        }
    }

    struct WatchItem: Decodable, Identifiable, Hashable, CompanionRetainedDataSized {
        let id: String
        let title: String
        let language: String?

        private enum CodingKeys: String, CodingKey { case id, title, name, language }

        var companionRetainedBytes: Int {
            id.utf8.count + title.utf8.count + (language?.utf8.count ?? 0)
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? values.decode(String.self, forKey: .id) {
                guard let identifier = normalizedCompanionStringID(string) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id, in: values, debugDescription: "Item IDs must be nonblank and at most 256 bytes."
                    )
                }

                id = identifier
            } else {
                let number = try values.decode(Int.self, forKey: .id)
                guard let identifier = companionNumericItemID(number) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id, in: values, debugDescription: "Item IDs must be positive."
                    )
                }

                id = identifier
            }
            let decodedTitle = (try? values.decode(String.self, forKey: .title))
                ?? (try? values.decode(String.self, forKey: .name))
            title = normalizedCompanionTitle(decodedTitle, fallback: String(localized: "Untitled"))
            language = normalizedCompanionLanguage(try? values.decodeIfPresent(String.self, forKey: .language))
        }
    }

    @MainActor
    final class WatchSession: ObservableObject {
        static let policy = CompanionPlatformPolicy.policy(for: .watchOS)
        enum Section: String, CaseIterable, Identifiable {
            case pads = "Pads"
            case questions = "Questions"
            var id: Self {
                self
            }

            var displayName: String {
                companionSectionDisplayName(rawValue)
            }
        }

        @Published var section: Section = .pads {
            didSet {
                if section != oldValue {
                    items.removeAll()
                    query = ""
                }
            }
        }

        @Published var items: [WatchItem] = []
        @Published var query = ""
        @Published var isLoading = false
        @Published var error: String?
        @Published var provisioningConnectionError: String?
        @Published var lastCredentialCheckSucceeded: Bool?
        private var reloadActivity = CompanionReloadActivity()
        private var reloadOrder = CompanionReloadOrder()

        private let defaults = UserDefaults.standard
        private var server: URL? {
            defaults.url(forKey: "watch.server")
        }

        private var apiKey: String? {
            WatchCredentialStore.apiKey
        }

        var isProvisioned: Bool {
            server != nil && apiKey?.isEmpty == false
        }

        var visibleItems: [WatchItem] {
            let normalizedQuery = normalizedCompanionSearchQuery(query)
            return normalizedQuery.isEmpty
                ? items
                : items.filter { $0.title.localizedCaseInsensitiveContains(normalizedQuery) }
        }

        var sections: [Section] {
            Section.allCases.filter { Self.policy.browsableSections.contains($0.rawValue.lowercased()) }
        }

        init() {
            activateProvisioningConnection()
        }

        func activateProvisioningConnection() {
            provisioningConnectionError = nil
            EmbeddedWatchProvisioningReceiver.shared.activate(
                provision: { [weak self] payload in self?.provision(from: payload) ?? false },
                provisioningPersisted: { [weak self] payload in self?.finishProvisioning(from: payload) },
                activationCompleted: { [weak self] error in self?.provisioningConnectionError = error }
            )
        }

        private func provision(from payload: EmbeddedWatchProvisioningPayload) -> Bool {
            guard let request = TVProvisioningRequest(dictionary: payload.dictionary) else {
                error = String(localized: "Invalid provisioning link.")
                return false
            }

            return applyProvisioningRequest(request)
        }

        @discardableResult
        private func applyProvisioningRequest(_ request: TVProvisioningRequest) -> Bool {
            guard WatchCredentialStore.save(apiKey: request.apiKey) else {
                error = String(localized: "Could not store the API key.")
                return false
            }

            finishProvisioning(request)
            return true
        }

        private func finishProvisioning(from payload: EmbeddedWatchProvisioningPayload) {
            guard TVProvisioningRequest(dictionary: payload.dictionary) != nil else { return }

            finishProvisioningState()
        }

        private func finishProvisioning(_ request: TVProvisioningRequest) {
            defaults.set(request.server, forKey: "watch.server")
            finishProvisioningState()
        }

        private func finishProvisioningState() {
            lastCredentialCheckSucceeded = nil
            query = ""
            items.removeAll()
            error = nil
            Task { await reload() }
        }

        func reload() async {
            guard let server, let apiKey else { return }

            reloadActivity.begin()
            let reloadID = reloadOrder.begin()
            isLoading = reloadActivity.isLoading
            defer {
                reloadActivity.end()
                isLoading = reloadActivity.isLoading
            }
            do {
                let path = section == .pads ? "api/pads" : "api/questions"
                let loadedItems: [WatchItem] = try await loadAllCompanionItems(
                    server: server, path: path, apiKey: apiKey
                )
                guard reloadOrder.isCurrent(reloadID) else { return }

                items = loadedItems
                error = nil
                lastCredentialCheckSucceeded = true
            } catch {
                if isCompanionCancellation(error) {
                    return
                }
                guard reloadOrder.isCurrent(reloadID) else { return }

                self.error = error.localizedDescription
                lastCredentialCheckSucceeded = false
            }
        }
    }

    private struct EmbeddedWatchProvisioningPayload {
        let server: String
        let apiKey: String
        let revision: UInt64?

        nonisolated init?(_ payload: [String: Any]) {
            guard let server = payload["server"] as? String,
                  let apiKey = payload["apiKey"] as? String else { return nil }

            self.server = server
            self.apiKey = apiKey
            revision = (payload["revision"] as? String).flatMap(UInt64.init)
        }

        nonisolated var dictionary: [String: Any] {
            var result: [String: Any] = ["server": server, "apiKey": apiKey]
            if let revision {
                result["revision"] = String(revision)
            }
            return result
        }
    }

    @MainActor
    private final class EmbeddedWatchProvisioningReceiver: NSObject {
        static let shared = EmbeddedWatchProvisioningReceiver()

        private var session: WCSession?
        private var provision: ((EmbeddedWatchProvisioningPayload) -> Bool)?
        private var provisioningPersisted: ((EmbeddedWatchProvisioningPayload) -> Void)?
        private var activationCompleted: ((String?) -> Void)?
        private nonisolated static let revisionDefaultsKey = "watch.latestProvisioningRevision"
        private nonisolated static let revisionLock = NSLock()

        override private init() {
            super.init()
        }

        func activate(
            provision: @escaping (EmbeddedWatchProvisioningPayload) -> Bool,
            provisioningPersisted: @escaping (EmbeddedWatchProvisioningPayload) -> Void,
            activationCompleted: @escaping (String?) -> Void
        ) {
            self.provision = provision
            self.provisioningPersisted = provisioningPersisted
            self.activationCompleted = activationCompleted
            guard WCSession.isSupported() else {
                activationCompleted(String(localized: "The iPhone connection is unavailable on this device."))
                return
            }

            let session = WCSession.default
            self.session = session
            session.delegate = self
            session.activate()

            if let payload = EmbeddedWatchProvisioningPayload(session.receivedApplicationContext) {
                _ = apply(payload)
            }
        }

        private nonisolated func receive(_ payload: [String: Any]) {
            guard let payload = EmbeddedWatchProvisioningPayload(payload) else { return }

            Task { @MainActor in
                _ = self.apply(payload)
            }
        }

        private nonisolated func notifyProvisioned(_ payload: EmbeddedWatchProvisioningPayload) {
            Task { @MainActor in
                self.provisioningPersisted?(payload)
            }
        }

        private func apply(_ payload: EmbeddedWatchProvisioningPayload) -> Bool {
            let defaults = UserDefaults.standard
            let latest = UInt64(defaults.string(forKey: Self.revisionDefaultsKey) ?? "")
            guard shouldApplyWatchProvisioningRevision(payload.revision, latest: latest) else { return true }
            guard provision?(payload) == true else { return false }

            if let revision = payload.revision {
                defaults.set(String(revision), forKey: Self.revisionDefaultsKey)
            }
            return true
        }
    }

    extension EmbeddedWatchProvisioningReceiver: WCSessionDelegate {
        nonisolated func session(
            _: WCSession,
            activationDidCompleteWith state: WCSessionActivationState,
            error: (any Error)?
        ) {
            let failure = watchConnectivityActivationFailure(
                isActivated: state == .activated,
                errorDescription: error?.localizedDescription
            )
            Task { @MainActor in
                self.activationCompleted?(failure)
            }
        }

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
            guard let payload = EmbeddedWatchProvisioningPayload(message) else {
                replyHandler(["ok": false, "errorCode": WatchProvisioningReplyError.invalidPayload.rawValue])
                return
            }
            guard let request = TVProvisioningRequest(dictionary: payload.dictionary) else {
                replyHandler(["ok": false, "errorCode": WatchProvisioningReplyError.invalidPayload.rawValue])
                return
            }

            Self.revisionLock.lock()
            defer { Self.revisionLock.unlock() }
            let defaults = UserDefaults.standard
            let latest = UInt64(defaults.string(forKey: Self.revisionDefaultsKey) ?? "")
            guard shouldApplyWatchProvisioningRevision(payload.revision, latest: latest) else {
                replyHandler(["ok": true])
                return
            }
            guard WatchCredentialStore.save(apiKey: request.apiKey) else {
                replyHandler(["ok": false, "errorCode": WatchProvisioningReplyError.saveFailed.rawValue])
                return
            }

            defaults.set(request.server, forKey: "watch.server")
            if let revision = payload.revision {
                defaults.set(String(revision), forKey: Self.revisionDefaultsKey)
            }
            replyHandler(["ok": true])
            notifyProvisioned(payload)
        }

        nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
            receive(message)
        }
    }

    private nonisolated enum WatchCredentialStore {
        private static let service = "com.adamdangoor.padbuddy.watch"
        private static let account = "coderpad-api-key"

        static var apiKey: String? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }

            return String(data: data, encoding: .utf8)
        }

        static func save(apiKey: String) -> Bool {
            let data = Data(apiKey.utf8)
            let update = [kSecValueData as String: data]
            let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            if status == errSecSuccess {
                return true
            }
            guard status == errSecItemNotFound else { return false }

            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }

        private static var baseQuery: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }
    }

    private struct WatchRootView: View {
        @EnvironmentObject private var session: WatchSession

        var body: some View {
            if session.isProvisioned {
                NavigationStack {
                    List {
                        Picker("Browse", selection: $session.section) {
                            ForEach(session.sections) { Text($0.displayName).tag($0) }
                        }
                        ForEach(session.visibleItems) { item in
                            NavigationLink(value: item) { Text(item.title).lineLimit(2) }
                        }
                        Section {
                            Label(
                                credentialHealthLabel,
                                systemImage: credentialHealthIcon
                            )
                            Text(WatchSession.policy.unsupportedActionGuidance)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(session.section.displayName)
                    .searchable(text: $session.query)
                    .navigationDestination(for: WatchItem.self) { WatchItemView(item: $0) }
                    .overlay { statusOverlay }
                    .task(id: session.section) { await session.reload() }
                }
            } else {
                let connectionError = session.error ?? session.provisioningConnectionError
                ContentUnavailableView {
                    if connectionError == nil {
                        Label("Connect CoderPad", systemImage: "link")
                    } else {
                        Label("Could Not Connect", systemImage: "exclamationmark.triangle")
                    }
                } description: {
                    if let connectionError {
                        Text(connectionError)
                    } else {
                        Text("Open a provisioning link from your companion device.")
                    }
                } actions: {
                    if session.provisioningConnectionError != nil {
                        Button("Retry") { session.activateProvisioningConnection() }
                    }
                }
            }
        }

        private var credentialHealthLabel: String {
            switch session.lastCredentialCheckSucceeded {
            case true: String(localized: "Account connection verified")
            case false: String(localized: "Account connection needs attention")
            case nil: String(localized: "Account connection not checked yet")
            }
        }

        private var credentialHealthIcon: String {
            switch session.lastCredentialCheckSucceeded {
            case true: "checkmark.shield"
            case false: "exclamationmark.triangle"
            case nil: "clock"
            }
        }

        @ViewBuilder private var statusOverlay: some View {
            if session.isLoading {
                ProgressView()
            } else if let error = session.error {
                ContentUnavailableView {
                    Label("Could not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await session.reload() } }
                }
            } else if session.visibleItems.isEmpty {
                ContentUnavailableView.search(text: session.query)
            }
        }
    }

    private struct WatchItemView: View {
        let item: WatchItem

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.headline)
                    if let language = item.language {
                        Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
#endif
