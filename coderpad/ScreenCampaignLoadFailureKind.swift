//
//  ScreenCampaignLoadFailureKind.swift
//  coderpad
//
//  Failure classification for Screen campaign loading. Kept outside SwiftUI view
//  files so task-group workers can classify errors off the main actor.
//

nonisolated enum ScreenCampaignLoadFailureKind {
    case authorization
    case other

    nonisolated init(error: any Error) {
        if (error as? CoderPadError)?.isUnauthorized == true {
            self = .authorization
        } else {
            self = .other
        }
    }
}
