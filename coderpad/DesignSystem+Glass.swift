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
                .background(.black.opacity(0.12), in: .rect(cornerRadius: 34))
                .glassBackgroundEffect(in: .rect(cornerRadius: 34), displayMode: .always)
                .overlay(.white.opacity(0.08), in: .rect(cornerRadius: 34))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .clipShape(.rect(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
                .offset(z: 18)
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                padding(14)
                    .background(.black.opacity(0.12), in: .rect(cornerRadius: 34))
                    .glassBackgroundEffect(in: .rect(cornerRadius: 34), displayMode: .always)
                    .overlay(.white.opacity(0.08), in: .rect(cornerRadius: 34))
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 34, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder
    func visionListRowHoverLift() -> some View {
        #if os(visionOS)
            listRowHoverEffect(.lift)
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                listRowHoverEffect(.lift)
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
                background(tint.opacity(0.20), in: Capsule())
                    .glassBackgroundEffect(in: Capsule(), displayMode: .implicit)
                    .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
            } else {
                background(.primary.opacity(0.08), in: Capsule())
                    .glassBackgroundEffect(in: Capsule(), displayMode: .implicit)
                    .overlay(Capsule().stroke(.primary.opacity(0.16), lineWidth: 1))
            }
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                if let tint {
                    background(tint.opacity(0.20), in: Capsule())
                        .glassBackgroundEffect(in: Capsule(), displayMode: .implicit)
                        .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
                } else {
                    background(.primary.opacity(0.08), in: Capsule())
                        .glassBackgroundEffect(in: Capsule(), displayMode: .implicit)
                        .overlay(Capsule().stroke(.primary.opacity(0.16), lineWidth: 1))
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
            background(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                       in: .rect(cornerRadius: 12))
                .glassBackgroundEffect(in: .rect(cornerRadius: 12), displayMode: .implicit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.14),
                                lineWidth: 1)
                )
        #elseif os(iOS)
            if PlatformIdiom.usesVisionInterface {
                background(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                           in: .rect(cornerRadius: 12))
                    .glassBackgroundEffect(in: .rect(cornerRadius: 12), displayMode: .implicit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.14),
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
