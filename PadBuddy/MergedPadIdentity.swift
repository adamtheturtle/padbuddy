import Foundation

nonisolated enum MergedPadIdentity {
    static func validated(_ raw: String) -> String? {
        guard raw.utf8.count <= 64, let id = PadIDValidation.normalize(raw), id == raw else { return nil }

        return id
    }
}
