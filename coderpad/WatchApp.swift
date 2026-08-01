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

    struct WatchItem: Decodable, Identifiable, Hashable {
        let id: String
        let title: String
        let language: String?

        private enum CodingKeys: String, CodingKey { case id, title, name, language }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? values.decode(String.self, forKey: .id) {
                id = string
            } else {
                id = try String(values.decode(Int.self, forKey: .id))
            }
            title = (try? values.decode(String.self, forKey: .title))
                ?? (try? values.decode(String.self, forKey: .name))
                ?? "Untitled"
            language = try? values.decodeIfPresent(String.self, forKey: .language)
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
        }

        @Published var section: Section = .pads {
            didSet {
                if section != oldValue {
                    query = ""
                }
            }
        }

        @Published var items: [WatchItem] = []
        @Published var query = ""
        @Published var isLoading = false
        @Published var error: String?
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
            query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }

        var sections: [Section] {
            Section.allCases.filter { Self.policy.browsableSections.contains($0.rawValue.lowercased()) }
        }

        init() {
            EmbeddedWatchProvisioningReceiver.shared.activate { [weak self] payload in
                self?.provision(from: payload) ?? false
            }
        }

        private func provision(from payload: EmbeddedWatchProvisioningPayload) -> Bool {
            guard let request = TVProvisioningRequest(dictionary: payload.dictionary) else {
                error = "Invalid provisioning link."
                return false
            }

            return applyProvisioningRequest(request)
        }

        @discardableResult
        private func applyProvisioningRequest(_ request: TVProvisioningRequest) -> Bool {
            guard WatchCredentialStore.save(apiKey: request.apiKey) else {
                error = "Could not store the API key."
                return false
            }

            defaults.set(request.server, forKey: "watch.server")
            error = nil
            return true
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
                let loadedItems = try await loadAllCompanionItems(server: server, path: path, apiKey: apiKey)
                guard reloadOrder.isCurrent(reloadID) else { return }

                items = loadedItems
                error = nil
                lastCredentialCheckSucceeded = true
            } catch {
                guard reloadOrder.isCurrent(reloadID) else { return }

                self.error = error.localizedDescription
                lastCredentialCheckSucceeded = false
            }
        }
    }

    private struct EmbeddedWatchProvisioningPayload {
        let server: String
        let apiKey: String

        nonisolated init?(_ payload: [String: Any]) {
            guard let server = payload["server"] as? String,
                  let apiKey = payload["apiKey"] as? String else { return nil }

            self.server = server
            self.apiKey = apiKey
        }

        nonisolated var dictionary: [String: Any] {
            ["server": server, "apiKey": apiKey]
        }
    }

    @MainActor
    private final class EmbeddedWatchProvisioningReceiver: NSObject {
        static let shared = EmbeddedWatchProvisioningReceiver()

        private var session: WCSession?
        private var provision: ((EmbeddedWatchProvisioningPayload) -> Bool)?

        override private init() {
            super.init()
        }

        func activate(provision: @escaping (EmbeddedWatchProvisioningPayload) -> Bool) {
            self.provision = provision
            guard WCSession.isSupported() else { return }

            let session = WCSession.default
            self.session = session
            session.delegate = self
            session.activate()

            if let payload = EmbeddedWatchProvisioningPayload(session.receivedApplicationContext) {
                _ = provision(payload)
            }
        }

        private nonisolated func receive(_ payload: [String: Any]) {
            guard let payload = EmbeddedWatchProvisioningPayload(payload) else { return }

            Task { @MainActor in
                _ = self.provision?(payload)
            }
        }
    }

    extension EmbeddedWatchProvisioningReceiver: WCSessionDelegate {
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
            guard let payload = EmbeddedWatchProvisioningPayload(message) else {
                replyHandler(["ok": false, "error": "Invalid provisioning payload."])
                return
            }
            guard let request = TVProvisioningRequest(dictionary: payload.dictionary) else {
                replyHandler(["ok": false, "error": "Invalid provisioning payload."])
                return
            }
            guard WatchCredentialStore.save(apiKey: request.apiKey) else {
                replyHandler(["ok": false, "error": "The Apple Watch could not save this account."])
                return
            }

            UserDefaults.standard.set(request.server, forKey: "watch.server")
            replyHandler(["ok": true])
            receive(message)
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
                            ForEach(session.sections) { Text($0.rawValue).tag($0) }
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
                    .navigationTitle(session.section.rawValue)
                    .searchable(text: $session.query)
                    .navigationDestination(for: WatchItem.self) { WatchItemView(item: $0) }
                    .overlay { statusOverlay }
                    .task(id: session.section) { await session.reload() }
                }
            } else {
                ContentUnavailableView {
                    if session.error == nil {
                        Label("Connect CoderPad", systemImage: "link")
                    } else {
                        Label("Could Not Connect", systemImage: "exclamationmark.triangle")
                    }
                } description: {
                    if let error = session.error {
                        Text(error)
                    } else {
                        Text("Open a provisioning link from your companion device.")
                    }
                }
            }
        }

        private var credentialHealthLabel: String {
            switch session.lastCredentialCheckSucceeded {
            case true: "Account connection verified"
            case false: "Account connection needs attention"
            case nil: "Account connection not checked yet"
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
