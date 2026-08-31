#if os(tvOS)
    import Combine
    import Security
    import SwiftUI

    @main
    struct CoderpadTVApp: App {
        @StateObject private var session = TVSession()

        var body: some Scene {
            WindowGroup {
                TVRootView()
                    .environmentObject(session)
            }
        }
    }

    struct TVItem: Decodable, Identifiable, Hashable, CompanionRetainedDataSized {
        let id: String
        let title: String
        let language: String?

        private enum CodingKeys: String, CodingKey { case id, title, name, language }

        var companionRetainedBytes: Int {
            id.utf8.count + title.utf8.count + (language?.utf8.count ?? 0)
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(CompanionItemID.self, forKey: .id).value
            let decodedTitle = (try? values.decode(String.self, forKey: .title))
                ?? (try? values.decode(String.self, forKey: .name))
            title = normalizedCompanionTitle(decodedTitle, fallback: String(localized: "Untitled"))
            language = normalizedCompanionLanguage(try? values.decodeIfPresent(String.self, forKey: .language))
        }
    }

    @MainActor
    final class TVSession: ObservableObject {
        static let policy = CompanionPlatformPolicy.policy(for: .tvOS)
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
                    language = nil
                    query = ""
                }
            }
        }

        @Published var items: [TVItem] = []
        @Published private(set) var query = ""
        @Published var language: String?
        @Published var isLoading = false
        @Published var error: String?
        private var reloadActivity = CompanionReloadActivity()
        private var reloadOrder = CompanionReloadOrder()

        func updateQuery(_ value: String) {
            query = boundedCompanionSearchInput(value)
        }

        private let defaults = UserDefaults.standard
        private var server: URL? {
            TVCredentialStore.credentials?.server
        }

        private var apiKey: String? {
            TVCredentialStore.credentials?.apiKey
        }

        var isProvisioned: Bool {
            server != nil && apiKey?.isEmpty == false
        }

        var languages: [String] {
            var labelsByKey: [String: String] = [:]
            // First spelling wins. The `default:` here was inert — the subscript
            // assigned unconditionally — so the *last* row carrying a key supplied the
            // label, and a campaign mixing `Python` and `python` showed whichever
            // spelling the API happened to return last, which could change between
            // refreshes of unchanged data (#4821). `WidgetSync.titles(forFavorites:in:)`
            // and `FavoriteTitleSync.adoptCloudTitles` pin the same thing down.
            for value in items.compactMap(\.language) {
                let key = companionLanguageKey(value)
                if labelsByKey[key] == nil {
                    labelsByKey[key] = value
                }
            }
            return labelsByKey.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        var visibleItems: [TVItem] {
            let normalizedQuery = normalizedCompanionSearchQuery(query)
            return items.filter { item in
                (normalizedQuery.isEmpty || item.title.localizedCaseInsensitiveContains(normalizedQuery))
                    && (language == nil
                        || item.language.map(companionLanguageKey) == language.map(companionLanguageKey))
            }
        }

        func provision(serverText: String, apiKey: String) {
            guard let request = TVProvisioningRequest(
                dictionary: ["server": serverText, "apiKey": apiKey]
            ) else {
                error = String(localized: "Enter a valid HTTPS server and API key.")
                return
            }

            // Server and key in one write, so a crash between them cannot pair a new key
            // with the old server (#4654).
            let credentials = CompanionCredentials(server: request.server, apiKey: request.apiKey)
            guard TVCredentialStore.save(credentials) else {
                error = String(localized: "The API key could not be stored securely.")
                return
            }

            // The Keychain item is the record now; the defaults copy remains only so an
            // older build reading it does not see a half-provisioned state.
            defaults.set(request.server, forKey: TVCredentialStore.legacyServerDefaultsKey)
            error = nil
        }

        func disconnect() {
            // Clear the Keychain first. Dropping the server URL while the API key
            // remains would show a disconnected UI that still holds credentials (#4659).
            guard TVCredentialStore.delete() else {
                error = String(localized: "The API key could not be removed from the Keychain.")
                return
            }

            defaults.removeObject(forKey: "tv.server")
            items.removeAll()
            query = ""
            language = nil
            error = nil
        }

        func reload() async {
            guard let server, let apiKey, !apiKey.isEmpty else { return }

            reloadActivity.begin()
            let reloadID = reloadOrder.begin()
            isLoading = reloadActivity.isLoading
            defer {
                reloadActivity.end()
                isLoading = reloadActivity.isLoading
            }
            do {
                let path = section == .pads ? "api/pads" : "api/questions"
                let loadedItems: [TVItem] = try await loadAllCompanionItems(
                    server: server, path: path, apiKey: apiKey
                )
                guard reloadOrder.isCurrent(reloadID) else { return }

                items = loadedItems
                if let language,
                   !languages.contains(where: { companionLanguageKey($0) == companionLanguageKey(language) }) {
                    // A filter that disappeared server-side leaves the picker bound to a
                    // value it no longer offers and hides every loaded row (#4678).
                    self.language = nil
                }
                error = nil
            } catch {
                if isCompanionCancellation(error) {
                    return
                }
                guard reloadOrder.isCurrent(reloadID) else { return }

                self.error = error.localizedDescription
            }
        }
    }

    private enum TVCredentialStore {
        private static let service = "com.adamdangoor.padbuddy.tv"
        private static let account = "coderpad-api-key"

        static let legacyServerDefaultsKey = "tv.server"

        /// The provisioned pair, as one committed value. A legacy item holding the key
        /// alone is adopted only when the defaults still carry a valid server, so a
        /// half-written pair is never used (#4654).
        static var credentials: CompanionCredentials? {
            guard let data = storedData else { return nil }

            if let credentials = CompanionCredentials(encoded: data) {
                return credentials
            }

            return CompanionCredentials.legacy(
                apiKeyData: data,
                storedServer: UserDefaults.standard.url(forKey: legacyServerDefaultsKey)
            )
        }

        static var apiKey: String? {
            credentials?.apiKey
        }

        private static var storedData: Data? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }

            return data
        }

        /// One Keychain write commits the server and key together.
        static func save(_ credentials: CompanionCredentials) -> Bool {
            let data = credentials.encoded
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

        @discardableResult
        static func delete() -> Bool {
            companionKeychainDeletionSucceeded(SecItemDelete(baseQuery as CFDictionary))
        }

        private static var baseQuery: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }
    }

    private struct TVRootView: View {
        @EnvironmentObject private var session: TVSession

        var body: some View {
            if session.isProvisioned {
                NavigationSplitView {
                    List(TVSession.Section.allCases, selection: $session.section) { section in
                        Label(section.displayName, systemImage: section == .pads ? "doc.text" : "questionmark.bubble")
                    }
                    .navigationTitle("CoderPad")
                } detail: {
                    TVItemsView()
                }
                .task(id: session.section) { await session.reload() }
            } else {
                TVProvisioningView()
            }
        }
    }

    private struct TVProvisioningView: View {
        @EnvironmentObject private var session: TVSession
        @State private var server = "https://app.coderpad.io"
        @State private var apiKey = ""

        var body: some View {
            Form {
                Section {
                    TextField("CoderPad server", text: $server)
                        .textContentType(.URL)
                    SecureField("API key", text: $apiKey)
                        .textContentType(.password)
                    Button("Connect") {
                        session.provision(serverText: server, apiKey: apiKey)
                    }
                    .disabled(server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel(String(localized: "Connection failed: \(error)"))
                    }
                } header: {
                    Label("Connect CoderPad", systemImage: "link.badge.plus")
                } footer: {
                    Text("Enter the API key on this Apple TV. Credentials are never placed in a link.")
                }
            }
            .navigationTitle("Connect CoderPad")
        }
    }

    private struct TVItemsView: View {
        @EnvironmentObject private var session: TVSession

        var body: some View {
            List(session.visibleItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    if let language = item.language {
                        Text(language).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(TVSession.policy.unsupportedActionGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .navigationTitle(session.section.displayName)
            .searchable(text: Binding(
                get: { session.query },
                set: { session.updateQuery($0) }
            ))
            .safeAreaInset(edge: .top) {
                if !session.languages.isEmpty {
                    Menu(session.language ?? "All languages") {
                        Button("All languages") { session.language = nil }
                        ForEach(session.languages, id: \.self) { language in
                            Button(language) { session.language = language }
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
            .overlay {
                if session.isLoading {
                    ProgressView()
                } else if let error = session.error {
                    ContentUnavailableView {
                        Label("Could not Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await session.reload() } }
                        Button("Change Credentials") { session.disconnect() }
                    }
                } else if session.visibleItems.isEmpty {
                    ContentUnavailableView.search(text: session.query)
                }
            }
        }
    }
#endif
