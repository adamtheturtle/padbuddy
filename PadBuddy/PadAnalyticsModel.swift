import Foundation
import Observation

@Observable
final class PadAnalyticsModel {
    private(set) var pad: Pad?
    private(set) var error: String?
    private(set) var loading = false
    private(set) var identity: PadDetailLoadIdentity?
    private var generation = 0

    func load(client: CoderPadClient, identity: PadDetailLoadIdentity) async {
        generation += 1
        let requestGeneration = generation
        self.identity = identity
        pad = nil
        error = nil
        loading = true
        do {
            let result = try await client.getPad(id: identity.padID)
            guard self.identity == identity, generation == requestGeneration, !Task.isCancelled else { return }

            pad = result
            loading = false
        } catch is CancellationError {
            if self.identity == identity, generation == requestGeneration {
                loading = false
            }
        } catch {
            guard self.identity == identity, generation == requestGeneration, !Task.isCancelled else { return }

            self.error = String(error.localizedDescription.prefix(500))
            loading = false
        }
    }
}

nonisolated enum PadTranscriptAvailability: Equatable {
    case unavailable
    case notProvided
    case empty
    case available

    init(_ pad: Pad) {
        if pad.transcriptSourceUnavailable == true {
            self = .unavailable
        } else if let transcript = pad.transcript {
            self = transcript.isEmpty ? .empty : .available
        } else {
            self = .notProvided
        }
    }
}
