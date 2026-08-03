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

    struct TVItem: Decodable, Identifiable, Hashable {
        let id: String
        let title: String
        let language: String?

        private enum CodingKeys: String, CodingKey { case id, title, name, language }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? values.decode(String.self, forKey: .id) {
                guard let identifier = normalizedCompanionStringID(string) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id, in: values, debugDescription: "Item IDs cannot be blank."
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
        @Published var query = ""
        @Published var language: String?
        @Published var isLoading = false
        @Published var error: String?
        private var reloadActivity = CompanionReloadActivity()
        private var reloadOrder = CompanionReloadOrder()

        private let defaults = UserDefaults.standard
        private var server: URL? {
            defaults.url(forKey: "tv.server")
        }

        private var apiKey: String? {
            TVCredentialStore.apiKey
        }

        var isProvisioned: Bool {
            server != nil && apiKey?.isEmpty == false
        }

        var languages: [String] {
            var labelsByKey: [String: String] = [:]
            for value in items.compactMap(\.language) {
                labelsByKey[companionLanguageKey(value), default: value] = value
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
            guard TVCredentialStore.save(apiKey: request.apiKey) else {
                error = String(localized: "The API key could not be stored securely.")
                return
            }

            defaults.set(request.server, forKey: "tv.server")
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
                let loadedItems = try await loadAllCompanionItems(server: server, path: path, apiKey: apiKey)
                guard reloadOrder.isCurrent(reloadID) else { return }

                items = loadedItems
                error = nil
            } catch {
                if isCompanionCancellation(error) { return }
                guard reloadOrder.isCurrent(reloadID) else { return }

                self.error = error.localizedDescription
            }
        }
    }

    private enum TVCredentialStore {
        private static let service = "com.adamdangoor.padbuddy.tv"
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
            .searchable(text: $session.query)
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
                    }
                } else if session.visibleItems.isEmpty {
                    ContentUnavailableView.search(text: session.query)
                }
            }
        }
    }
#endif
