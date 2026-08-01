import Foundation

nonisolated struct TVProvisioningRequest: Equatable {
    private static let serverKey = "server"
    private static let apiKeyKey = "apiKey"

    let server: URL
    let apiKey: String

    init?(dictionary: [String: Any]) {
        guard let serverText = dictionary[Self.serverKey] as? String,
              let key = dictionary[Self.apiKeyKey] as? String else { return nil }

        self.init(serverText: serverText, apiKey: key)
    }

    private init?(serverText: String, apiKey keyText: String) {
        guard let server = URL(string: serverText), server.scheme == "https", server.host != nil,
              server.user == nil, server.password == nil, server.query == nil,
              server.fragment == nil else { return nil }

        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        self.server = server
        apiKey = key
    }

    static func payload(server: URL, apiKey: String) -> [String: String] {
        [
            serverKey: server.absoluteString,
            apiKeyKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
    }
}

#if os(iOS)
    extension TVProvisioningRequest {
        static func payload(for account: Account) -> [String: String]? {
            guard !account.isMock else { return nil }

            let apiKey = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty, !account.hasMalformedBaseURLOverride else { return nil }

            return payload(server: account.resolvedBaseURL, apiKey: apiKey)
        }
    }
#endif
