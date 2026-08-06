//
//  SettingsView+Vision.swift
//  coderpad
//

#if os(visionOS)
    import SwiftUI

    extension SettingsView {
        var visionAccountEmptyState: some View {
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 48, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("No accounts")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("Add an account with a CoderPad API key.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    Button("Add Account") {
                        beginAddingAccount()
                    }
                    .prominentActionButtonStyle()

                    GetAPIKeyLink()
                        .font(.body.weight(.semibold))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }
#endif
