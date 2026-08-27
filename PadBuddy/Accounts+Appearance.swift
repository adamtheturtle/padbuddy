//
//  Accounts+Appearance.swift
//  coderpad
//
//  Names for the curated avatar glyphs and tints, so each choice can announce
//  itself rather than every option sharing one label.
//

import Foundation

extension Account {
    /// What each curated glyph depicts. VoiceOver announced every option as
    /// "Account icon", so the choices were indistinguishable and could not be picked
    /// deliberately (#4561). SF Symbols expose no localized name of their own.
    static func iconSymbolName(_ symbol: String) -> String {
        switch symbol {
        case "building.2.fill": String(localized: "Office buildings")
        case "briefcase.fill": String(localized: "Briefcase")
        case "person.2.fill": String(localized: "Two people")
        case "house.fill": String(localized: "House")
        case "star.fill": String(localized: "Star")
        case "flag.fill": String(localized: "Flag")
        case "hammer.fill": String(localized: "Hammer")
        case "globe.americas.fill": String(localized: "Globe")
        default: String(localized: "Account icon")
        }
    }

    /// The colour name for a curated tint. Every swatch announced itself as
    /// "Account color", which told a VoiceOver user nothing about which one they were
    /// choosing (#4562).
    static func tintName(_ hex: String) -> String {
        switch hex.uppercased() {
        case "#3478F6": String(localized: "Blue")
        case "#9B59B6": String(localized: "Purple")
        case "#FF2D55": String(localized: "Pink")
        case "#FF3B30": String(localized: "Red")
        case "#FF9500": String(localized: "Orange")
        case "#34C759": String(localized: "Green")
        case "#30B0C7": String(localized: "Teal")
        case "#8E8E93": String(localized: "Gray")
        default: String(localized: "Account color")
        }
    }
}
