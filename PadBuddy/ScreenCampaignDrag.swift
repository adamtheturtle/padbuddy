//
//  ScreenCampaignDrag.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let coderpadScreenCampaign = UTType(
        exportedAs: "com.coderpad.screen-campaign", conformingTo: .data
    )
}

/// A structured internal identity plus a bounded plain-text proxy for external
/// pasteboards. Remote control/format characters never leave the app (#1469).
nonisolated struct ScreenCampaignDragPayload: Codable, Transferable, Equatable {
    static let maximumNameLength = 200

    let id: Int
    let name: String

    init(campaign: ScreenCampaign) {
        id = campaign.id
        let cleaned = String(campaign.name.unicodeScalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return category != .control && category != .format
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        name = cleaned.isEmpty
            ? "Campaign #\(campaign.id)"
            : String(cleaned.prefix(Self.maximumNameLength))
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .coderpadScreenCampaign)
        ProxyRepresentation { $0.name }
    }
}
