// swiftlint:disable file_length

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
                unsupportedActionGuidance: String(
                    localized: "This companion is read only. Use PadBuddy on iPhone, iPad, or Mac to make changes."
                )
            )
        }
    }
}

let maxCompanionPageCount = 100
let maxCompanionPageBytes = 2 * 1024 * 1024
let maxCompanionItemCount = 1000
/// Bounds strings retained across every decoded page, independent of response size.
let maxCompanionRetainedBytes = 512 * 1024
let maxCompanionPageTokenBytes = 256
/// Row identities are metadata, not content; keep hashing and SwiftUI diffing bounded.
let maxCompanionItemIDBytes = 256
/// Language identifiers are short metadata labels shown in a tvOS menu.
let maxCompanionLanguageBytes = 64
/// Titles remain useful in compact rows without allowing pathological layout work.
let maxCompanionTitleBytes = 512
let maxCompanionTitleCharacters = 160

enum CompanionLoadError: LocalizedError, Equatable {
    case pageLimitExceeded(Int)
    case responsePageTooLarge(Int)
    case itemLimitExceeded(Int)
    case retainedDataLimitExceeded(Int)
    case pageTokenTooLong(Int)
    case missingItemCollection(String)
    case duplicateItemIdentity
    case unauthorized
    case forbidden
    case rateLimited
    case serverFailure(Int)
    case httpFailure(Int)

    var errorDescription: String? {
        switch self {
        case let .pageLimitExceeded(limit):
            String(localized: "CoderPad returned more than \(limit) pages. Loading stopped to protect this device.")
        case let .responsePageTooLarge(limit):
            String(localized: "A CoderPad response exceeded the \(limit)-byte safety limit. Loading stopped.")
        case let .itemLimitExceeded(limit):
            String(localized: "CoderPad returned more than \(limit) items. Loading stopped to protect this device.")
        case let .retainedDataLimitExceeded(limit):
            String(localized: "CoderPad returned over \(limit) bytes of item data. Loading stopped.")
        case let .pageTokenTooLong(limit):
            String(localized: "CoderPad returned a page token longer than \(limit) bytes. Loading stopped.")
        case let .missingItemCollection(name):
            String(localized: "The CoderPad response did not contain its expected \(name) collection.")
        case .duplicateItemIdentity:
            String(localized: "CoderPad returned the same item more than once. Loading stopped.")
        case .unauthorized:
            String(localized: "The API key was rejected. Reconnect this companion from PadBuddy.")
        case .forbidden:
            String(localized: "This account is not allowed to open this section.")
        case .rateLimited:
            String(localized: "CoderPad is rate limiting this companion. Try again later.")
        case let .serverFailure(status):
            String(localized: "CoderPad returned server error \(status). Try again later.")
        case let .httpFailure(status):
            String(localized: "CoderPad returned HTTP \(status).")
        }
    }
}

func companionHTTPStatusError(_ status: Int) -> CompanionLoadError? {
    switch status {
    case 200 ..< 300: nil
    case 401: .unauthorized
    case 403: .forbidden
    case 429: .rateLimited
    case 500 ... 599: .serverFailure(status)
    default: .httpFailure(status)
    }
}

func companionItemLimitExceeded(current: Int, adding: Int) -> Bool {
    current > maxCompanionItemCount || adding > maxCompanionItemCount - current
}

func companionRetainedByteLimitExceeded(current: Int, adding: Int) -> Bool {
    current > maxCompanionRetainedBytes || adding > maxCompanionRetainedBytes - current
}

protocol CompanionRetainedDataSized {
    var companionRetainedBytes: Int { get }
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

func companionNumericItemID(_ value: Int) -> String? {
    value > 0 ? String(value) : nil
}

func normalizedCompanionStringID(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty || normalized.utf8.count > maxCompanionItemIDBytes ? nil : normalized
}

func isCompanionCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

nonisolated func watchConnectivityActivationFailure(isActivated: Bool, errorDescription: String?) -> String? {
    if let errorDescription, !errorDescription.isEmpty {
        return String(localized: "Could not activate the iPhone connection: \(errorDescription)")
    }
    return isActivated ? nil : String(localized: "Could not activate the iPhone connection. Try again.")
}

nonisolated func iPhoneWatchActivationFailure(isActivated: Bool, errorDescription: String?) -> String? {
    if let errorDescription, !errorDescription.isEmpty {
        return String(localized: "Could not activate the Apple Watch connection: \(errorDescription)")
    }
    return isActivated ? nil : String(localized: "Could not activate the Apple Watch connection. Try again.")
}

func normalizedCompanionSearchQuery(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

func companionLanguageKey(_ value: String) -> String {
    value.lowercased()
}

func normalizedCompanionLanguage(_ value: String?) -> String? {
    guard let value else { return nil }

    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty || normalized.utf8.count > maxCompanionLanguageBytes ? nil : normalized
}

func companionSectionDisplayName(_ identifier: String) -> String {
    switch identifier.lowercased() {
    case "pads": String(localized: "Pads")
    case "questions": String(localized: "Questions")
    default: identifier
    }
}

/// Reduces remote companion titles to one safe display line. Whitespace is collapsed,
/// while control and Unicode format scalars (including bidi overrides) are discarded.
func normalizedCompanionTitle(_ value: String?, fallback: String) -> String {
    var normalized = ""
    var byteCount = 0
    var pendingSpace = false
    for scalar in (value ?? "").unicodeScalars {
        if scalar.properties.isWhitespace {
            pendingSpace = !normalized.isEmpty
            continue
        }
        if scalar.properties.generalCategory == .format || CharacterSet.controlCharacters.contains(scalar) {
            continue
        }

        let text = String(scalar)
        let addedBytes = text.utf8.count + (pendingSpace ? 1 : 0)
        guard byteCount + addedBytes <= maxCompanionTitleBytes else { break }

        if pendingSpace {
            normalized.append(" ")
            byteCount += 1
            pendingSpace = false
        }
        normalized.append(text)
        byteCount += text.utf8.count
    }
    let bounded = String(normalized.prefix(maxCompanionTitleCharacters))
    return bounded.isEmpty ? fallback : bounded
}

func companionCollectionName(for path: String) -> String? {
    switch path.split(separator: "/").last {
    case "pads": "pads"
    case "questions": "questions"
    default: nil
    }
}

func hasDuplicateCompanionIDs<S: Sequence>(_ ids: S) -> Bool where S.Element: Hashable {
    var seen = Set<S.Element>()
    return ids.contains { !seen.insert($0).inserted }
}

struct CompanionReloadActivity {
    private(set) var activeReloads = 0
    var isLoading: Bool {
        activeReloads > 0
    }

    mutating func begin() {
        activeReloads += 1
    }

    mutating func end() {
        activeReloads = max(0, activeReloads - 1)
    }
}

struct CompanionReloadOrder {
    private var latest: UUID?

    mutating func begin() -> UUID {
        let identifier = UUID()
        latest = identifier
        return identifier
    }

    func isCurrent(_ identifier: UUID) -> Bool {
        latest == identifier
    }
}

struct CompanionPageToken: Decodable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            value = try container.decode(String.self)
        } catch DecodingError.typeMismatch {
            do {
                let number = try container.decode(Int.self)
                guard let token = companionNumericPageToken(number) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Page numbers must be positive."
                    )
                }

                value = token
            } catch let error as DecodingError {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "A companion page token must be a string or positive integer. \(error)"
                )
            }
        }
    }
}

#if os(watchOS) || os(tvOS)

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

        func items(named name: String) -> [Item]? {
            switch name {
            case "pads": pads
            case "questions": questions
            default: results
            }
        }
    }

    private func appendCompanionPageItems<Item: Decodable & Identifiable & CompanionRetainedDataSized>(
        from envelope: CompanionPage<Item>, named collectionName: String,
        to items: inout [Item], seenIDs: inout Set<Item.ID>, retainedBytes: inout Int
    ) throws where Item.ID: Hashable {
        guard let pageItems = envelope.items(named: collectionName) else {
            throw CompanionLoadError.missingItemCollection(collectionName)
        }
        guard !companionItemLimitExceeded(current: items.count, adding: pageItems.count) else {
            throw CompanionLoadError.itemLimitExceeded(maxCompanionItemCount)
        }

        let pageRetainedBytes = pageItems.reduce(0) { $0 + $1.companionRetainedBytes }
        guard !companionRetainedByteLimitExceeded(current: retainedBytes, adding: pageRetainedBytes) else {
            throw CompanionLoadError.retainedDataLimitExceeded(maxCompanionRetainedBytes)
        }

        var candidateIDs = seenIDs
        guard pageItems.allSatisfy({ candidateIDs.insert($0.id).inserted }) else {
            throw CompanionLoadError.duplicateItemIdentity
        }

        seenIDs = candidateIDs
        retainedBytes += pageRetainedBytes
        items.append(contentsOf: pageItems)
    }

    private func companionResponseData(for request: URLRequest, session: URLSession) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if let statusError = companionHTTPStatusError(http.statusCode) {
            throw statusError
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

    private func validatedDirectCompanionItems<Item: Identifiable & CompanionRetainedDataSized>(
        _ items: [Item]
    ) throws -> [Item] where Item.ID: Hashable {
        guard !companionItemLimitExceeded(current: 0, adding: items.count) else {
            throw CompanionLoadError.itemLimitExceeded(maxCompanionItemCount)
        }

        let retainedBytes = items.reduce(0) { $0 + $1.companionRetainedBytes }
        guard !companionRetainedByteLimitExceeded(current: 0, adding: retainedBytes) else {
            throw CompanionLoadError.retainedDataLimitExceeded(maxCompanionRetainedBytes)
        }
        guard !hasDuplicateCompanionIDs(items.map(\.id)) else {
            throw CompanionLoadError.duplicateItemIdentity
        }

        return items
    }

    func loadAllCompanionItems<Item: Decodable & Identifiable & CompanionRetainedDataSized>(
        server: URL,
        path: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [Item] where Item.ID: Hashable {
        var items: [Item] = []
        var seenItemIDs = Set<Item.ID>()
        var retainedBytes = 0
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
                return try validatedDirectCompanionItems(direct)
            }
            let envelope = try JSONDecoder().decode(CompanionPage<Item>.self, from: data)
            let collectionName = companionCollectionName(for: path) ?? "results"
            try appendCompanionPageItems(
                from: envelope, named: collectionName, to: &items,
                seenIDs: &seenItemIDs, retainedBytes: &retainedBytes
            )
            guard let next = nonBlankCompanionPageToken(envelope.nextPage?.value) else { return items }

            if let error = companionPageTokenLengthError(next) {
                throw error
            }
            guard seenPages.insert(next).inserted else { throw URLError(.badServerResponse) }

            page = next
        }
    }
#endif
