//
//  ScreenAPI+Pagination.swift
//  coderpad
//
//  Offset/limit pagination for `GET /tests` and the tolerant page decoding that
//  skips malformed items without dropping the rest of the page (#764). Split from
//  ScreenAPI.swift to keep that file within the lint length limit.
//

import Foundation

// MARK: - Pagination

/// One page of test sessions from `GET /tests`. Unlike the Interview API's
/// cursor-URL pagination, Screen uses offset/limit: pass `nextStart` as the next
/// request's `start` while `hasMoreItems` is true.
nonisolated struct ScreenTestsPage: Decodable, Hashable {
    let tests: [ScreenTestSession]
    let discardedTestCount: Int
    let pagination: ScreenPagination?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try Self.decodeTests(from: container)
        tests = decoded.tests
        discardedTestCount = decoded.discardedCount
        pagination = try container.decodeIfPresent(ScreenPagination.self, forKey: .pagination)
    }

    enum CodingKeys: String, CodingKey {
        case tests, pagination
    }

    private static func decodeTests(from container: KeyedDecodingContainer<CodingKeys>)
        throws -> (tests: [ScreenTestSession], discardedCount: Int) {
        var testsContainer = try container.nestedUnkeyedContainer(forKey: .tests)

        var decoded: [ScreenTestSession] = []
        var discardedCount = 0
        while !testsContainer.isAtEnd {
            if let test = try? testsContainer.decode(ScreenTestSession.self) {
                decoded.append(test)
            } else if (try? testsContainer.decode(DiscardedScreenValue.self)) == nil {
                break
            } else {
                discardedCount += 1
            }
        }
        return (decoded, discardedCount)
    }
}

/// A tolerantly decoded JSON array: malformed elements are skipped rather than
/// failing the whole response, so one bad item can't hide every valid one
/// (#764 for sessions, #896 for campaigns).
nonisolated struct TolerantScreenList<Element: Decodable>: Decodable {
    let elements: [Element]
    let discardedCount: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        var discardedCount = 0
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else if (try? container.decode(DiscardedScreenValue.self)) == nil {
                break
            } else {
                discardedCount += 1
            }
        }
        elements = decoded
        self.discardedCount = discardedCount
    }
}

nonisolated struct ScreenCampaignListResult: Equatable {
    let campaigns: [ScreenCampaign]
    let discardedCount: Int

    var diagnostic: String? {
        guard discardedCount > 0 else { return nil }

        let noun = discardedCount == 1 ? "record" : "records"
        return "Ignored \(discardedCount) malformed campaign \(noun) from Screen."
    }
}

nonisolated struct ScreenTestListResult: Equatable {
    let tests: [ScreenTestSession]
    let discardedCount: Int

    var diagnostic: String? {
        guard discardedCount > 0 else { return nil }

        let noun = discardedCount == 1 ? "record" : "records"
        return "Ignored \(discardedCount) malformed candidate session \(noun) from Screen."
    }
}

private nonisolated struct DiscardedScreenValue: Decodable {
    init(from decoder: any Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd {
                _ = try? array.decode(Self.self)
            }
            return
        }

        if let object = try? decoder.container(keyedBy: DiscardedScreenCodingKey.self) {
            for key in object.allKeys {
                _ = try? object.decode(Self.self, forKey: key)
            }
            return
        }

        _ = try? decoder.singleValueContainer()
    }
}

private nonisolated struct DiscardedScreenCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

nonisolated struct ScreenPagination: Decodable, Hashable {
    let start: Int?
    let limit: Int?
    let total: Int?
    let hasMoreItems: Bool
    let nextStart: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try? container.decodeIfPresent(Int.self, forKey: .start)
        let limit = try? container.decodeIfPresent(Int.self, forKey: .limit)
        let total = try? container.decodeIfPresent(Int.self, forKey: .total)
        let nextStart = try? container.decodeIfPresent(Int.self, forKey: .nextStart)
        guard start.map({ $0 >= 0 }) ?? true,
              limit.map({ $0 > 0 }) ?? true,
              total.map({ $0 >= 0 }) ?? true,
              nextStart.map({ $0 >= 0 }) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .start,
                in: container,
                debugDescription: "Screen pagination offsets/counts must be nonnegative and limit must be positive."
            )
        }

        self.start = start
        self.limit = limit
        self.total = total
        hasMoreItems = try container.decode(Bool.self, forKey: .hasMoreItems)
        self.nextStart = nextStart
    }

    enum CodingKeys: String, CodingKey {
        case start, limit, total
        case hasMoreItems = "has_more_items"
        case nextStart = "next_start"
    }
}
