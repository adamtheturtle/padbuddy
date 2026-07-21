//
//  FailureStatePreviews.swift
//  coderpad
//

#if DEBUG
    import Foundation
    import SwiftUI

    private struct PreviewAPIFailure: LocalizedError {
        var errorDescription: String? {
            "The preview server returned an unexpected response while loading pads."
        }
    }

    private struct FailureBannerPreviewStack: View {
        var body: some View {
            VStack(spacing: 16) {
                OfflineBanner()
                StaleRefreshBanner(
                    message: "The latest changes could not be downloaded. Data shown is from 12 minutes ago.",
                    retry: {}
                )
                APIErrorView(error: PreviewAPIFailure(), onRetry: {})
                    .frame(minHeight: 260)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.previewBackground)
        }
    }

    private extension Color {
        static var previewBackground: Color {
            #if os(macOS)
                Color(nsColor: .windowBackgroundColor)
            #else
                Color(uiColor: .systemBackground)
            #endif
        }
    }

    #Preview("Failure States — Regular") {
        FailureBannerPreviewStack()
            .frame(width: 680, height: 520)
    }

    #Preview("Failure States — Narrow") {
        FailureBannerPreviewStack()
            .frame(width: 390, height: 620)
    }

    #Preview("Failure States — Dark") {
        FailureBannerPreviewStack()
            .frame(width: 680, height: 520)
            .preferredColorScheme(.dark)
    }
#endif
