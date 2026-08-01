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
let maxCompanionPageBytes = 2 * 1024 * 1024
let maxCompanionItemCount = 1000
let maxCompanionPageTokenBytes = 256

enum CompanionLoadError: LocalizedError, Equatable {
    case pageLimitExceeded(Int)
    case responsePageTooLarge(Int)
    case itemLimitExceeded(Int)
    case pageTokenTooLong(Int)

    var errorDescription: String? {
        switch self {
        case let .pageLimitExceeded(limit):
            String(localized: "CoderPad returned more than \(limit) pages. Loading stopped to protect this device.")
        case let .responsePageTooLarge(limit):
            String(localized: "A CoderPad response exceeded the \(limit)-byte safety limit. Loading stopped.")
        case let .itemLimitExceeded(limit):
            String(localized: "CoderPad returned more than \(limit) items. Loading stopped to protect this device.")
        case let .pageTokenTooLong(limit):
            String(localized: "CoderPad returned a page token longer than \(limit) bytes. Loading stopped.")
        }
    }
}

func companionItemLimitExceeded(current: Int, adding: Int) -> Bool {
    current > maxCompanionItemCount || adding > maxCompanionItemCount - current
}

func companionPageTokenLengthError(_ value: String) -> CompanionLoadError? {
    value.utf8.count > maxCompanionPageTokenBytes ? .pageTokenTooLong(maxCompanionPageTokenBytes) : nil
}

func nonBlankCompanionPageToken(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    return value
}

func companionNumericPageToken(_ value: Int) -> String? {
    value > 0 ? String(value) : nil
}

#if os(watchOS) || os(tvOS)
    private struct CompanionPageToken: Decodable {
        let value: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else {
                let number = try container.decode(Int.self)
                guard let token = companionNumericPageToken(number) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Page numbers must be positive."
                    )
                }

                value = token
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

    private func companionResponseData(for request: URLRequest, session: URLSession) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        var data = Data()
        data.reserveCapacity(min(maxCompanionPageBytes, max(0, Int(http.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < maxCompanionPageBytes else {
                throw CompanionLoadError.responsePageTooLarge(maxCompanionPageBytes)
            }

            data.append(byte)
        }
        return data
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
            let data = try await companionResponseData(for: request, session: session)

            if page == nil, let direct = try? JSONDecoder().decode([Item].self, from: data) {
                guard !companionItemLimitExceeded(current: 0, adding: direct.count) else {
                    throw CompanionLoadError.itemLimitExceeded(maxCompanionItemCount)
                }

                return direct
            }
            let envelope = try JSONDecoder().decode(CompanionPage<Item>.self, from: data)
            guard !companionItemLimitExceeded(current: items.count, adding: envelope.items.count) else {
                throw CompanionLoadError.itemLimitExceeded(maxCompanionItemCount)
            }

            items.append(contentsOf: envelope.items)
            guard let next = nonBlankCompanionPageToken(envelope.nextPage?.value) else { return items }

            if let error = companionPageTokenLengthError(next) {
                throw error
            }
            guard seenPages.insert(next).inserted else { throw URLError(.badServerResponse) }

            page = next
        }
    }
#endif
