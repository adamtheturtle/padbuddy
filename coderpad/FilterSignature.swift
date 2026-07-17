//
//  FilterSignature.swift
//  coderpad
//
//  Collision-free change tokens for live filter tuples.
//

enum FilterSignature {
    static func make(_ fields: [String?]) -> String {
        fields.map(token).joined()
    }

    private static func token(_ field: String?) -> String {
        guard let field else { return "n;" }

        return "s\(field.utf8.count):\(field);"
    }
}
