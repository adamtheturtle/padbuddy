import Foundation

nonisolated enum QuestionInstructionNames {
    static func title(_ instruction: CandidateInstruction, index: Int) -> String {
        if let name = instruction.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return String(localized: "Part \(index + 1)")
    }

    static func normalized(_ name: String) -> String? {
        let characters = name.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
        let bounded = String(characters.joined().trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return bounded.isEmpty ? nil : bounded
    }

    static func renamed(_ instructions: [CandidateInstruction], edit: InstructionNameEdit,
                        name: String) -> [CandidateInstructionPayload]? {
        let matches = instructions.indices.filter {
            instructions[$0].instructions == edit.instruction.instructions
                && instructions[$0].name == edit.instruction.name
        }
        let index: Int
        if instructions.indices.contains(edit.index), matches.contains(edit.index) {
            index = edit.index
        } else if matches.count == 1, let moved = matches.first {
            index = moved
        } else {
            return nil
        }
        var payloads = instructions.map {
            CandidateInstructionPayload(instructions: $0.instructions, defaultVisible: $0.defaultVisible, name: $0.name)
        }
        payloads[index].name = normalized(name)
        return payloads
    }
}

nonisolated struct InstructionNameEdit: Identifiable {
    let id = UUID()
    let index: Int
    let instruction: CandidateInstruction
    let questionID: Int
    let accountID: UUID?
    let clientIdentity: ClientTaskIdentity
}
