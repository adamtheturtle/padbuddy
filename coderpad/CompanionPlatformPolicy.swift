import Foundation

struct CompanionPlatformPolicy: Equatable {
    enum Platform { case watchOS, tvOS }

    let browsableSections: [String]
    let allowsMutations: Bool
    let allowsSettings: Bool
    let unsupportedActionGuidance: String

    static func policy(for platform: Platform) -> Self {
        switch platform {
        case .watchOS, .tvOS:
            Self(
                browsableSections: ["pads", "questions"],
                allowsMutations: false,
                allowsSettings: false,
                unsupportedActionGuidance: "This companion is read only. "
                    + "Use PadBuddy on iPhone, iPad, or Mac to make changes."
            )
        }
    }
}

let maxCompanionPageCount = 100

enum CompanionLoadError: LocalizedError, Equatable {
    case pageLimitExceeded(Int)

    var errorDescription: String? {
        switch self {
        case let .pageLimitExceeded(limit):
            String(localized: "CoderPad returned more than \(limit) pages. Loading stopped to protect this device.")
        }
    }
}

#if os(watchOS) || os(tvOS)
    private struct CompanionPageToken: Decodable {
        let value: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else {
                value = try String(container.decode(Int.self))
            }
        }
    }

    private struct CompanionPage<Item: Decodable>: Decodable {
        let results: [Item]?
        let pads: [Item]?
        let questions: [Item]?
        let nextPage: CompanionPageToken?

        enum CodingKeys: String, CodingKey {
            case results
            case pads
            case questions
            case nextPage = "next_page"
        }

        var items: [Item] {
            results ?? pads ?? questions ?? []
        }
    }

    func loadAllCompanionItems<Item: Decodable>(
        server: URL,
        path: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [Item] {
        var items: [Item] = []
        var page: String?
        var seenPages = Set<String>()
        var pageCount = 0

        while true {
            pageCount += 1
            guard pageCount <= maxCompanionPageCount else {
                throw CompanionLoadError.pageLimitExceeded(maxCompanionPageCount)
            }

            var components = URLComponents(
                url: server.appending(path: path),
                resolvingAgainstBaseURL: false
            )
            if let page {
                components?.queryItems = [URLQueryItem(name: "page", value: page)]
            }
            guard let url = components?.url else { throw URLError(.badURL) }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            if page == nil, let direct = try? JSONDecoder().decode([Item].self, from: data) {
                return direct
            }
            let envelope = try JSONDecoder().decode(CompanionPage<Item>.self, from: data)
            items.append(contentsOf: envelope.items)
            guard let next = envelope.nextPage?.value, !next.isEmpty else { return items }
            guard seenPages.insert(next).inserted else { throw URLError(.badServerResponse) }

            page = next
        }
    }
#endif
