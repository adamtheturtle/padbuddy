//
//  PadBuddyTests+MergedOrderToken.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged favorites order tie-break token")
struct MergedOrderTokenTests {
    /// Two Macs hold the same cross-account order under different local account
    /// UUIDs — `Account.id` is per-device random, which is why the cloud blob keys on
    /// the sync identity. A token spelled with the UUID made each device compare a
    /// different pair of strings, so `cloud < local` could answer differently on each
    /// side and neither adopted the other's order (#4812).
    @Test func `the token is identical on two devices with different account UUIDs`() {
        let refs: [FavoriteRef] = [.pad("abc"), .question(7)]
        let deviceA = UUID()
        let deviceB = UUID()
        let orderA = refs.map { MergedFavoriteRef(account: deviceA, ref: $0) }
        let orderB = refs.map { MergedFavoriteRef(account: deviceB, ref: $0) }

        let tokenA = FavoritesOrderStore.token(for: orderA, syncID: { _ in "identity-1" })
        let tokenB = FavoritesOrderStore.token(for: orderB, syncID: { _ in "identity-1" })

        #expect(tokenA == tokenB)
    }

    @Test func `two accounts sharing one ref still produce distinct tokens`() {
        let first = UUID()
        let second = UUID()
        let identities = [first: "identity-1", second: "identity-2"]
        let syncID: (UUID) -> String? = { identities[$0] }

        let one = FavoritesOrderStore.token(
            for: [MergedFavoriteRef(account: first, ref: .pad("abc"))], syncID: syncID
        )
        let two = FavoritesOrderStore.token(
            for: [MergedFavoriteRef(account: second, ref: .pad("abc"))], syncID: syncID
        )

        #expect(one != two)
    }

    /// An account with no sync identity cannot be in the cloud order at all, so it
    /// contributes only its ref rather than a per-device UUID.
    @Test func `an unmapped account contributes no device-local identifier`() {
        let account = UUID()

        let token = FavoritesOrderStore.token(
            for: [MergedFavoriteRef(account: account, ref: .pad("abc"))], syncID: { _ in nil }
        )

        #expect(!token.contains(account.uuidString))
        #expect(token.contains("p:abc"))
    }

    @Test func `order is part of the token`() {
        let account = UUID()
        let syncID: (UUID) -> String? = { _ in "identity-1" }
        let refs: [FavoriteRef] = [.pad("abc"), .question(7)]

        let forward = FavoritesOrderStore.token(
            for: refs.map { MergedFavoriteRef(account: account, ref: $0) }, syncID: syncID
        )
        let reversed = FavoritesOrderStore.token(
            for: refs.reversed().map { MergedFavoriteRef(account: account, ref: $0) }, syncID: syncID
        )

        #expect(forward != reversed)
    }
}
