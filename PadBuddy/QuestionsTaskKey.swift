//
//  QuestionsTaskKey.swift
//  coderpad
//
//  Restart key for the questions list's per-session load task, split from
//  QuestionsView.swift to keep that file under the file-length limit.
//

import SwiftUI

struct QuestionsTaskKey: Hashable {
    let apiKey: String
    let baseURL: URL?
    let phase: ScenePhase
}

struct MergedQuestionsTaskKey: Hashable {
    let accountKey: [MergedAccountToken]
    let phase: ScenePhase
}
