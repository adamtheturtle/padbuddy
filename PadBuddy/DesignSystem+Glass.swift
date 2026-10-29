//
//  DesignSystem+Glass.swift
//  coderpad
//
//  Most Liquid Glass styling now uses SwiftUI 26 APIs directly. This keeps the
//  app-coupled "Get an API key" link, which depends on the CoderPad-specific
//  `CoderPadLinks`.
//

import SwiftUI

extension View {
    @ViewBuilder
    func glassActionButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.bordered)
        #else
            buttonStyle(.glass)
        #endif
    }

    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.borderedProminent)
        #else
            buttonStyle(.glassProminent)
        #endif
    }

    @ViewBuilder
    func visionSpatialPanel() -> some View {
        #if os(visionOS)
            padding(14)
                .background(.black.opacity(0.20), in: .rect(cornerRadius: 34))
                .glassBackgroundEffect(in: .rect(cornerRadius: 34), displayMode: .always)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.white.opacity(0.13))
                        .allowsHitTesting(false)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .clipShape(.rect(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
                .offset(z: 18)
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                padding(14)
                    .background(.black.opacity(0.20), in: .rect(cornerRadius: 34))
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(.white.opacity(0.13))
                            .allowsHitTesting(false)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
                    .clipShape(.rect(cornerRadius: 34, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder
    func visionSpatialSplitPanel(leadingClearance: CGFloat) -> some View {
        #if os(visionOS)
            padding(14)
                .background(alignment: .leading) {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: leadingClearance)
                        Color.clear
                            .background(.black.opacity(0.20), in: .rect(cornerRadius: 34))
                            .glassBackgroundEffect(in: .rect(cornerRadius: 34), displayMode: .always)
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .fill(.white.opacity(0.13))
                                    .allowsHitTesting(false)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(.white.opacity(0.24), lineWidth: 1)
                                    .allowsHitTesting(false)
                            )
                            .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
                    }
                }
                .offset(z: 18)
        #else
            visionSpatialPanel()
        #endif
    }

    @ViewBuilder
    func visionListRowHoverLift() -> some View {
        #if os(visionOS)
            listRowHoverEffect(.lift)
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                hoverEffect(.lift)
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        #if os(visionOS)
            if let tint {
                background(tint.opacity(0.26), in: Capsule())
                    .glassBackgroundEffect(in: Capsule(), displayMode: .implicit)
                    .overlay(Capsule().stroke(tint.opacity(0.68), lineWidth: 1))
            } else {
                background(.primary.opacity(0.12), in: Capsule())
                    .glassBackgroundEffect(in: Capsule(), displayMode: .implicit)
                    .overlay(Capsule().stroke(.primary.opacity(0.24), lineWidth: 1))
            }
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                if let tint {
                    background(tint.opacity(0.26), in: Capsule())
                        .overlay(Capsule().stroke(tint.opacity(0.68), lineWidth: 1))
                } else {
                    background(.primary.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(.primary.opacity(0.24), lineWidth: 1))
                }
            } else if let tint {
                background(tint.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
            } else {
                glassEffect(.regular, in: Capsule())
            }
        #else
            glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: Capsule())
        #endif
    }

    @ViewBuilder
    func selectableGlassRoundedRectangle(isSelected: Bool) -> some View {
        #if os(visionOS)
            background(isSelected ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.10),
                       in: .rect(cornerRadius: 12))
                .glassBackgroundEffect(in: .rect(cornerRadius: 12), displayMode: .implicit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.78) : Color.primary.opacity(0.22),
                                lineWidth: 1)
                )
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                background(isSelected ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.10),
                           in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.78) : Color.primary.opacity(0.22),
                                    lineWidth: 1)
                    )
            } else {
                glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.24)) : .regular.interactive(),
                            in: .rect(cornerRadius: 12))
            }
        #else
            glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.24)) : .regular.interactive(),
                        in: .rect(cornerRadius: 12))
        #endif
    }

    @ViewBuilder
    func visionDetailSecondaryLabel() -> some View {
        #if os(visionOS)
            foregroundStyle(Color.secondary.opacity(0.96))
        #else
            foregroundStyle(.secondary)
        #endif
    }

    @ViewBuilder
    func detailChipBarBackground() -> some View {
        #if os(visionOS)
            self
        #else
            background(.bar)
        #endif
    }

    @ViewBuilder
    func detailChipBarOverflowMask() -> some View {
        #if os(visionOS)
            self
        #else
            mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
        #endif
    }

    @ViewBuilder
    func visionRailBackground() -> some View {
        #if os(visionOS)
            background(.primary.opacity(0.12), in: Capsule())
                .glassBackgroundEffect(in: Capsule(), displayMode: .always)
                .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                background(.primary.opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder
    func visionRailHover() -> some View {
        #if os(visionOS)
            hoverEffect(.lift)
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                hoverEffect(.lift)
            } else {
                self
            }
        #else
            self
        #endif
    }
}

struct GetAPIKeyLink: View {
    var prominent: Bool = false

    /// Drive the open explicitly through the environment action rather than a bare
    /// `Link`. On iPad a `Link` to an external URL can silently no-op (#552); calling
    /// `openURL` from a `Button` opens the browser reliably on both macOS and iPadOS.
    @Environment(\.openURL) private var openURL

    var body: some View {
        let button = Button {
            openURL(CoderPadLinks.apiSettings)
        } label: {
            Label("Get an API key from CoderPad", systemImage: "key.viewfinder")
        }

        if prominent {
            button.prominentActionButtonStyle()
        } else {
            // Borderless keeps the chromeless, accent-tinted hyperlink look the old
            // `Link` had on both macOS and iPadOS, rather than a bordered push button.
            button.buttonStyle(.borderless)
        }
    }
}
