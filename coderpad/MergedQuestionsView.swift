//
//  MergedQuestionsView.swift
//  coderpad
//
//  The combined "All Accounts" questions list: every real account's questions in
//  one merged, sorted list with per-account badges. Mirrors `MergedPadsView`;
//  per-row actions and the detail pane route to the originating account through
//  `MergedRouting`. View-building members live in `+List`/`+Bars`/`+Logic`
//  extensions to keep this declaration within the `type_body_length` budget.
//

import AppKit
import SwiftUI

struct MergedQuestionsView: View {
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) var scenePhase
    @State var accounts = AccountsStore.shared
    @State var router = MergedRouting.shared
    @State var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var nav = AppNavigation.shared
    @State var questionsByAccount: [UUID: [Question]] = [:]
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false

    @Binding var selection: Question?
    @State var selectedQuestionID: Int?
    @Binding var search: String

    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    @State var draftFilter: String?
    @State var accountFilter: UUID?
    @State var mineOnly = false
    @State var favoritesOnly = false
    @AppStorage(QuestionSort.storageKey) var sort: QuestionSort = .lastUsedDesc
    @State var creatingForAccount: Account?

    var body: some View {
        decorated
    }
}
