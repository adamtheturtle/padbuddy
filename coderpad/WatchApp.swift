#if os(watchOS)
import Combine
import Security
import SwiftUI

@main
struct CoderpadWatchApp: App {
    @StateObject private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(session)
                .onOpenURL { session.provision(from: $0) }
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
            id = String(try values.decode(Int.self, forKey: .id))
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
        var id: Self { self }
    }

    @Published var section: Section = .pads
    @Published var items: [WatchItem] = []
    @Published var query = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastCredentialCheckSucceeded: Bool?

    private let defaults = UserDefaults.standard
    private var server: URL? { defaults.url(forKey: "watch.server") }
    private var apiKey: String? { WatchCredentialStore.apiKey }
    var isProvisioned: Bool { server != nil && apiKey?.isEmpty == false }
    var visibleItems: [WatchItem] {
        query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var sections: [Section] {
        Section.allCases.filter { Self.policy.browsableSections.contains($0.rawValue.lowercased()) }
    }

    func provision(from url: URL) {
        guard let request = TVProvisioningRequest(url: url) else {
            error = "Invalid provisioning link."
            return
        }
        guard WatchCredentialStore.save(apiKey: request.apiKey) else {
            error = "Could not store the API key."
            return
        }
        defaults.set(request.server, forKey: "watch.server")
        error = nil
        Task { await reload() }
    }

    func reload() async {
        guard let server, let apiKey else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: server.appending(path: section == .pads ? "api/pads" : "api/questions"))
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            items = try Self.decodeItems(data)
            error = nil
            lastCredentialCheckSucceeded = true
        } catch {
            self.error = error.localizedDescription
            lastCredentialCheckSucceeded = false
        }
    }

    private static func decodeItems(_ data: Data) throws -> [WatchItem] {
        if let items = try? JSONDecoder().decode([WatchItem].self, from: data) { return items }
        let envelope = try JSONDecoder().decode(ItemEnvelope.self, from: data)
        return envelope.results ?? envelope.pads ?? envelope.questions ?? []
    }

    private struct ItemEnvelope: Decodable {
        let results: [WatchItem]?
        let pads: [WatchItem]?
        let questions: [WatchItem]?
    }
}

private enum WatchCredentialStore {
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
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = Data(apiKey.utf8)
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
                            systemImage: session.lastCredentialCheckSucceeded == false
                                ? "exclamationmark.triangle" : "checkmark.shield"
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
                Label("Connect CoderPad", systemImage: "link")
            } description: {
                Text("Open a provisioning link from your companion device.")
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

    @ViewBuilder private var statusOverlay: some View {
        if session.isLoading {
            ProgressView()
        } else if let error = session.error {
            ContentUnavailableView("Could not Load", systemImage: "exclamationmark.triangle", description: Text(error))
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
