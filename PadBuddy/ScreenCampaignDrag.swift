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
        name = campaign.screenDisplayName
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .coderpadScreenCampaign)
        ProxyRepresentation { $0.name }
    }
}

nonisolated extension ScreenCampaign {
    var screenDisplayName: String {
        let cleaned = ExternalText.singleLine(name, limit: 256)
        return cleaned.isEmpty ? String(localized: "Untitled")
            : String(cleaned.unicodeScalars.prefix(ScreenCampaignDragPayload.maximumNameLength))
    }
}
