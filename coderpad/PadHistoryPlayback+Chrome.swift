//
//  PadHistoryPlayback+Chrome.swift
//  coderpad
//

import SwiftUI

extension View {
    func historyPlaybackBarChrome() -> some View {
        padding(6)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.secondary.opacity(0.14), lineWidth: 0.5)
            }
    }
}
