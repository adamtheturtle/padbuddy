//
//  QuestionDetailView+Banners.swift
//  coderpad
//

import SwiftUI

extension QuestionDetailView {
    var bottomBanners: some View {
        VStack(spacing: 8) {
            createPadFailureBanner
            undoDeletionBanner
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    var createPadFailureBanner: some View {
        if let createPadError {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(createPadError)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Retry") { Task { await createPadInline() } }
                    .disabled(isCreatingPad || isReadOnly)
                Button("Dismiss") { self.createPadError = nil }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.subtleStroke, lineWidth: 1))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Could not create pad. \(createPadError)")
        }
    }

    @ViewBuilder
    var undoDeletionBanner: some View {
        if deletionTask != nil {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text("Deleting “\(question.title.isEmpty ? "this question" : question.title)”…")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { cancelDeletion() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.subtleStroke, lineWidth: 1))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
