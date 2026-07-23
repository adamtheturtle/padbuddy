import Foundation

struct TVProvisioningRequest: Equatable {
    let server: URL
    let apiKey: String

    init?(url: URL) {
        guard url.scheme == "coderpad", url.host == "provision",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let serverText = components.queryItems?.first(where: { $0.name == "server" })?.value,
              let server = URL(string: serverText), server.scheme == "https", server.host != nil,
              server.user == nil, server.password == nil,
              let key = components.queryItems?.first(where: { $0.name == "apiKey" })?.value?
              .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }

        self.server = server
        apiKey = key
    }
}
