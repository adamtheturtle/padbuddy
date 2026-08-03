//
//  WidgetSharedTypes.swift
//  coderpad
//
//  The value types in the app <-> widget data contract, split from
//  WidgetPadSnapshot.swift to keep both files under the file-length limit.
//
//  The extension compiles its own copy of these (in
//  `RecentPadsWidget/WidgetSharedSnapshot.swift`) because the two folders are
//  synchronized to separate targets, so any change here must be mirrored there or
//  the JSON stops round-tripping. Depends on nothing but Foundation.
//

import AppGroupMailbox
import Foundation

/// A minimal, dependency-free projection of a `Pad` for display in the widget.
nonisolated struct WidgetPadSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

/// A configurable account choice the widget can pin. Mirrored from the app's
/// account list so the widget's configuration picker can populate its options from
/// inside the widget process. Kept in lock-step with the widget's copy.
nonisolated struct WidgetAccount: Codable, Identifiable, Hashable {
    /// Stable cross-device account identity used by configuration and snapshot files.
    let id: String
    let name: String
    /// The former device-local UUID, retained so existing widget configurations can
    /// resolve once and migrate to `id`.
    let legacyID: String?

    init(id: String, name: String, legacyID: String? = nil) {
        self.id = id
        self.name = name
        self.legacyID = legacyID
    }
}

/// A favourite question the New Pad widget button can be configured to seed a new
/// pad from. Mirrored per account so the configuration picker can list a pinned
/// account's favourites from inside the widget process. Kept in lock-step with the
/// widget's copy.
nonisolated struct WidgetQuestion: Codable, Identifiable, Hashable {
    /// CoderPad's per-org question id. Not unique across accounts, so the new-pad
    /// deep link always carries the owning account alongside it.
    let id: Int
    let title: String
}

/// A pending "create a new pad" request the widget/Control Center New Pad button
/// records for the app to perform on its next activation (the widget can't open the
/// app's custom URL scheme, #456/#485). Kept in lock-step with the widget's copy.
nonisolated struct WidgetNewPadRequest: Codable, Sendable {
    let id: UUID
    let account: String?
    let question: Int?

    init(account: String?, question: Int?, id: UUID = UUID()) {
        self.id = id
        self.account = account
        self.question = question
    }

    private enum CodingKeys: String, CodingKey {
        case id, account, question
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        account = try values.decodeIfPresent(String.self, forKey: .account)
        question = try values.decodeIfPresent(Int.self, forKey: .question)
    }
}

/// A pending "open an existing pad" request the iPad widget records for the app to
/// perform on its next activation (custom-scheme widget links are unreliable there,
/// #660). Kept in lock-step with the widget's copy.
nonisolated struct WidgetOpenPadRequest: Codable, Sendable {
    let id: String
    let account: String?
}

/// A pending handoff request of either kind, tagged so a drain can replay New Pad
/// and Open Pad requests together in the order the user issued them. Draining each
/// kind in its own loop let an older New Pad win over a newer Open Pad (#1045).
nonisolated enum WidgetPendingRequest: Codable, Sendable {
    case newPad(WidgetNewPadRequest)
    case openPad(WidgetOpenPadRequest)
}

/// A mailbox claim paired with its CoderPad-owned payload. The app acknowledges only after
/// routing completes, so a process termination during handling leaves the action recoverable.
nonisolated struct WidgetClaimedRequest {
    let request: WidgetPendingRequest
    private let claim: AppGroupMailbox<WidgetPendingRequest>.Claim

    init(request: WidgetPendingRequest, claim: AppGroupMailbox<WidgetPendingRequest>.Claim) {
        self.request = request
        self.claim = claim
    }

    func acknowledge() {
        try? claim.acknowledge()
    }
}
