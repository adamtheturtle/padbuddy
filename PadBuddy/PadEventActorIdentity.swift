import Foundation

/// Resolves name-only events only when the feed associates that name with one email.
struct PadEventActorIdentity {
    private var emailsByName: [String: String] = [:]
    private var ambiguousNames: Set<String> = []

    init(events: [PadEvent]) {
        for event in events {
            guard let name = Self.normalized(event.userName, limit: 120),
                  let email = Self.normalized(event.userEmail, limit: 254),
                  !ambiguousNames.contains(name) else { continue }

            if let existing = emailsByName[name], existing != email {
                emailsByName.removeValue(forKey: name)
                ambiguousNames.insert(name)
            } else {
                emailsByName[name] = email
            }
        }
    }

    func key(for event: PadEvent) -> String? {
        if let email = Self.normalized(event.userEmail, limit: 254) {
            return "email:\(email)"
        }
        // Never truncate an oversized identity into another person's key.
        if let raw = event.userEmail, raw.unicodeScalars.prefix(255).count > 254 {
            return nil
        }
        guard let name = Self.normalized(event.userName, limit: 120),
              !ambiguousNames.contains(name) else { return nil }

        return emailsByName[name].map { "email:\($0)" } ?? "name:\(name)"
    }

    static func preferredActor(_ previous: PadEvent, latest: PadEvent) -> PadEvent {
        let latestName = ExternalText.singleLine(latest.userName ?? "", limit: 120)
        if !latestName.isEmpty {
            return latest
        }
        let previousName = ExternalText.singleLine(previous.userName ?? "", limit: 120)
        return previousName.isEmpty ? latest : previous
    }

    private static func normalized(_ raw: String?, limit: Int) -> String? {
        guard let raw, raw.unicodeScalars.prefix(limit + 1).count <= limit else { return nil }

        let value = ExternalText.singleLine(raw, limit: limit).lowercased()
        return value.isEmpty ? nil : value
    }
}
