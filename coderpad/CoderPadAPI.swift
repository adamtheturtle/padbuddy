//
//  CoderPadAPI.swift
//  coderpad
//

import Foundation

struct Pad: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let state: String
    let ownerEmail: String
    let language: String?
    let participants: [String]
    let url: String
    let createdAt: Date?
    let updatedAt: Date?
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, state, language, participants, url
        case ownerEmail = "owner_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case endedAt = "ended_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "unknown"
        ownerEmail = (try? c.decodeIfPresent(String.self, forKey: .ownerEmail)) ?? ""
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        participants = (try? c.decodeIfPresent([String].self, forKey: .participants)) ?? []
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        endedAt = try? c.decodeIfPresent(Date.self, forKey: .endedAt)
    }
}

private struct PadsResponse: Decodable {
    let status: String
    let pads: [Pad]
}

enum CoderPadError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key. Open Settings to enter one."
        case .http(let code, let body):
            let snippet = body.prefix(300)
            return "HTTP \(code): \(snippet)"
        case .decode(let detail):
            return "Couldn't read response: \(detail)"
        }
    }
}

struct CoderPadClient {
    let apiKey: String
    let baseURL = URL(string: "https://app.coderpad.io")!
    let session: URLSession = .shared

    func listPads() async throws -> [Pad] {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }

        var request = URLRequest(url: baseURL.appendingPathComponent("/api/pads/"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoderPadError.http(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CoderPadError.http(http.statusCode, body)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PadsResponse.self, from: data).pads
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw CoderPadError.decode("missing key '\(key.stringValue)' at \(path(ctx.codingPath))")
        } catch let DecodingError.valueNotFound(type, ctx) {
            throw CoderPadError.decode("missing value of \(type) at \(path(ctx.codingPath))")
        } catch let DecodingError.typeMismatch(type, ctx) {
            throw CoderPadError.decode("type mismatch (\(type)) at \(path(ctx.codingPath)) — \(ctx.debugDescription)")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw CoderPadError.decode("corrupted at \(path(ctx.codingPath)) — \(ctx.debugDescription)")
        }
    }

    private func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.stringValue }.joined(separator: ".")
    }
}
