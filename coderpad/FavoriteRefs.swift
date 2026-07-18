//
//  FavoriteRefs.swift
//  coderpad
//
//  The reference types behind the sidebar's drag-ordered favourites, split from
//  FavoritesOrder.swift to keep that file within the lint length limit.
//

import Foundation

/// One sidebar favourite, regardless of kind, so a pad and a starred question can sit
/// in one drag-ordered list. The associated value is the kind's own identifier — a pad
/// slug or a per-org question id — matching the id each kind-specific store uses.
enum FavoriteRef: Codable, Hashable {
    case pad(String)
    case question(Int)
}

/// A favourite row in the combined "All Accounts" sidebar. Account identity has to be
/// part of the order key because pad slugs and question ids can collide across orgs.
struct MergedFavoriteRef: Codable, Hashable {
    let account: UUID
    let ref: FavoriteRef
}
