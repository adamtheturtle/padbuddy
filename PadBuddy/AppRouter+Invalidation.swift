//
//  AppRouter+Invalidation.swift
//  coderpad
//
//  Ordering a mutation broadcast behind the cache invalidation it implies.
//

import Foundation
import os
import SwiftUI

@MainActor
extension AppRouter {
    /// Serializes the invalidate-then-post sequences so broadcasts keep their order.
    private static var broadcastTail: Task<Void, Never>?

    /// Invalidates the coordinator's cached reads for `account`, and only then posts.
    ///
    /// The invalidation used to be an unstructured task while the post went out
    /// synchronously — and `NotificationCenter` delivers before `post` returns — so a
    /// consumer that reacted by reloading reached `APIReadCoordinator` with no ordering
    /// guarantee against the queued invalidation. When the read won, it was served from
    /// the coalescer's cache: up to 60 seconds old and, by construction, from before the
    /// mutation that triggered the broadcast, so the list repainted with stale
    /// pre-mutation rows and stayed that way until something else forced a refetch
    /// (#4763). Chaining on `broadcastTail` keeps successive broadcasts in order.
    private static func invalidate(
        _ account: UUID?,
        using invalidate: @escaping (UUID) async -> Void,
        thenPost post: @escaping @MainActor () -> Void
    ) {
        guard let account else {
            post()
            return
        }

        let previous = broadcastTail
        broadcastTail = Task { @MainActor in
            await previous?.value
            await invalidate(account)
            post()
        }
    }

    static func invalidatePads(for account: UUID?, thenPost post: @escaping @MainActor () -> Void) {
        invalidate(account, using: { await APIReadCoordinator.shared.invalidatePads(accountID: $0) },
                   thenPost: post)
    }

    static func invalidateQuestions(
        for account: UUID?, thenPost post: @escaping @MainActor () -> Void
    ) {
        invalidate(account, using: { await APIReadCoordinator.shared.invalidateQuestions(accountID: $0) },
                   thenPost: post)
    }
}
