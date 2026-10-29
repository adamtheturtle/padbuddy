import Foundation

nonisolated enum PadParticipantRefreshOutcome: Equatable {
    case loaded(Pad)
    case failed
    case cancelled
}

enum PadParticipantRefresh {
    static func load(
        id: String, fetch: (String) async throws -> Pad
    ) async -> PadParticipantRefreshOutcome {
        do {
            let pad = try await fetch(id)
            return PadDetailResponse.matches(requestedID: id, responseID: pad.id) ? .loaded(pad) : .failed
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            return .failed
        }
    }
}
