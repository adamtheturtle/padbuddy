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
                    .onOpenURL { session.provision(from: $0) }
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
    final class TVSession: ObservableObject {
        static let policy = CompanionPlatformPolicy.policy(for: .tvOS)
        enum Section: String, CaseIterable, Identifiable {
            case pads = "Pads"
            case questions = "Questions"
            var id: Self {
                self
            }
        }

        @Published var section: Section = .pads {
            didSet {
                if section != oldValue { language = nil }
            }
        }

        @Published var items: [TVItem] = []
        @Published var query = ""
        @Published var language: String?
        @Published var isLoading = false
        @Published var error: String?

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
            Array(Set(items.compactMap(\.language))).sorted()
        }

        var visibleItems: [TVItem] {
            items.filter { item in
                (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
                    && (language == nil || item.language == language)
            }
        }

        func provision(from url: URL) {
            guard let request = TVProvisioningRequest(url: url) else {
                error = "That provisioning link is invalid."
                return
            }

            defaults.set(request.server, forKey: "tv.server")
            guard TVCredentialStore.save(apiKey: request.apiKey) else {
                error = "The API key could not be stored securely."
                return
            }

            error = nil
            Task { await reload() }
        }

        func reload() async {
            guard let server, let apiKey, !apiKey.isEmpty else { return }

            isLoading = true
            defer { isLoading = false }
            do {
                let path = section == .pads ? "api/pads" : "api/questions"
                var request = URLRequest(url: server.appending(path: path))
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                items = try Self.decodeItems(data)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }

        private static func decodeItems(_ data: Data) throws -> [TVItem] {
            if let direct = try? JSONDecoder().decode([TVItem].self, from: data) { return direct }
            let envelope = try JSONDecoder().decode(ItemEnvelope.self, from: data)
            return envelope.results ?? envelope.pads ?? envelope.questions ?? []
        }

        private struct ItemEnvelope: Decodable {
            let results: [TVItem]?
            let pads: [TVItem]?
            let questions: [TVItem]?
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
            if status == errSecSuccess { return true }
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
                        Label(section.rawValue, systemImage: section == .pads ? "doc.text" : "questionmark.bubble")
                    }
                    .navigationTitle("CoderPad")
                } detail: {
                    TVItemsView()
                }
                .task(id: session.section) { await session.reload() }
            } else {
                ContentUnavailableView {
                    Label("Connect CoderPad", systemImage: "link.badge.plus")
                } description: {
                    Text("Open a CoderPad provisioning link from your iPhone, iPad, or Mac "
                        + "to browse pads and questions here.")
                }
            }
        }
    }

    private struct TVItemsView: View {
        @EnvironmentObject private var session: TVSession

        var body: some View {
            List(session.visibleItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    if let language = item.language { Text(language).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(TVSession.policy.unsupportedActionGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .navigationTitle(session.section.rawValue)
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
                    ContentUnavailableView(
                        "Could not Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if session.visibleItems.isEmpty {
                    ContentUnavailableView.search(text: session.query)
                }
            }
        }
    }
#endif
