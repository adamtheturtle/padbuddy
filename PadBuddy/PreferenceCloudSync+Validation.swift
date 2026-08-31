//
//  PreferenceCloudSync+Validation.swift
//  coderpad
//

import CoreFoundation
import Foundation
import os

enum PreferenceFilterSnapshotDecodeOutcome {
    case search(NamedSearch)
    case invalid(String)
}

enum PreferenceValueDisposition: Equatable {
    case value
    case deletion
    case invalid
}

extension PreferenceCloudSync {
    private static let booleanKeys: Set<String> = [
        "general.spotlightIndexing",
        "general.notifyOnPadUpdates",
        "general.hidePadTitlesInNotifications",
        "browser.openInBackground"
    ]
    private static let enumKeys: Set<String> = [
        "pads.sort", "questions.sort", "general.appearance", "general.presence", "general.dockBadgeScope"
    ]

    static func preferenceValueDisposition(_ value: Any?, forKey key: String) -> PreferenceValueDisposition {
        guard let value else { return .deletion }

        if booleanKeys.contains(key) {
            return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() ? .value : .invalid
        }
        if enumKeys.contains(key) {
            return enumValueDisposition(value, forKey: key)
        }

        switch key {
        case "browser.defaultBrowserBundleID":
            return validBundleID(value) ? .value : .invalid

        case "pads.merged.liveFilter", "questions.merged.liveFilter":
            guard let data = value as? Data,
                  NamedSearch.snapshotDataIsWithinLimit(data),
                  validFilterSnapshot(data) else { return .invalid }

            return .value

        default:
            return .invalid
        }
    }

    static func shouldAdoptCloudValue(_ cloud: Any, forKey key: String, local: Any?,
                                      cloudRevision: Double, localRevision: Double) -> Bool {
        shouldAdoptCloudValue(
            cloud, forKey: key, local: local,
            cloudRevision: PreferenceRevisionStamp(era: 0, revision: cloudRevision),
            localRevision: PreferenceRevisionStamp(era: 0, revision: localRevision)
        )
    }

    static func shouldAdoptCloudValue(
        _ cloud: Any, forKey key: String, local: Any?,
        cloudRevision: PreferenceRevisionStamp,
        localRevision: PreferenceRevisionStamp
    ) -> Bool {
        guard preferenceValueDisposition(cloud, forKey: key) == .value else { return false }
        guard !plistValuesEqual(local, cloud) else { return false }

        return cloudRevision > localRevision
            || (cloudRevision == localRevision && tieBreakFavorsCloud(local: local, cloud: cloud))
    }

    private static func enumValueDisposition(_ value: Any, forKey key: String) -> PreferenceValueDisposition {
        switch key {
        case "pads.sort": rawValueIsValid(value, as: PadSort.self)
        case "questions.sort": rawValueIsValid(value, as: QuestionSort.self)
        case "general.appearance": rawValueIsValid(value, as: AppAppearance.self)
        case "general.presence": rawValueIsValid(value, as: AppPresence.self)
        case "general.dockBadgeScope": rawValueIsValid(value, as: DockBadgeScope.self)
        default: .invalid
        }
    }

    private static func validBundleID(_ value: Any) -> Bool {
        guard let bundleID = value as? String, (1 ... 255).contains(bundleID.count) else { return false }

        return bundleID.allSatisfy { $0.isASCII && !$0.isWhitespace && !$0.isNewline }
    }

    private static func rawValueIsValid<Value: RawRepresentable>(
        _ value: Any,
        as _: Value.Type
    ) -> PreferenceValueDisposition
        where Value.RawValue == String {
        guard let raw = value as? String, Value(rawValue: raw) != nil else { return .invalid }

        return .value
    }

    static func decodeFilterSnapshot(
        _ data: Data,
        snapshot: (Data) throws -> MergedFilterSnapshot = {
            try SharedCoders.decoder.decode(MergedFilterSnapshot.self, from: $0)
        },
        legacy: (Data) throws -> NamedSearch = {
            try SharedCoders.decoder.decode(NamedSearch.self, from: $0)
        }
    ) -> PreferenceFilterSnapshotDecodeOutcome {
        guard NamedSearch.snapshotDataIsWithinLimit(data) else {
            return .invalid("Filter snapshot exceeds the maximum size")
        }

        do {
            return try .search(snapshot(data).search)
        } catch {
            let snapshotFailure = error.localizedDescription
            do {
                return try .search(legacy(data))
            } catch {
                let legacyFailure = error.localizedDescription
                return .invalid(
                    "Filter snapshot decode failed: \(snapshotFailure); legacy decode failed: \(legacyFailure)"
                )
            }
        }
    }

    private static func validFilterSnapshot(_ data: Data) -> Bool {
        let search: NamedSearch
        switch decodeFilterSnapshot(data) {
        case let .search(decoded):
            search = decoded
        case let .invalid(detail):
            persistenceLogger.error("Refused undecodable cloud filter snapshot: \(detail, privacy: .public)")
            return false
        }

        return (search.typeFilter == nil || FilterValueValidation.interviewType(search.typeFilter) != nil)
            && (search.draftFilter == nil || FilterValueValidation.draftState(search.draftFilter) != nil)
    }
}
