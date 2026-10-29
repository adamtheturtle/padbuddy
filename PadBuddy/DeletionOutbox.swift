import AppGroupMailbox
import CryptoKit
import Foundation

nonisolated struct DeletionWork: Codable, Sendable {
    enum Kind: String, Codable { case pad, question }
    let kind: Kind
    let recordID: String
    let account: UUID?
    let clientFingerprint: String
    let baseURL: URL

    init(kind: Kind, recordID: String, account: UUID?, identity: ClientTaskIdentity) {
        self.kind = kind
        self.recordID = recordID
        self.account = account
        clientFingerprint = Self.fingerprint(identity)
        baseURL = identity.baseURL
    }

    static func fingerprint(_ identity: ClientTaskIdentity) -> String {
        var hash = SHA256()
        hash.update(data: Data(identity.apiKey.utf8))
        hash.update(data: Data([0]))
        hash.update(data: Data(identity.baseURL.absoluteString.utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    var stableID: UUID {
        let key = "\(kind.rawValue):\(account?.uuidString ?? "legacy"):\(recordID):\(clientFingerprint)"
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// The delivery buffer is bounded; pending cleanup lives on disk until acknowledged.
nonisolated struct DeletionOutbox: Sendable {
    let mailbox: AppGroupMailbox<DeletionWork>

    init(root: URL, capacity: Int = 512) throws {
        mailbox = try AppGroupMailbox(
            containerURL: root, namespace: "deletion-cleanup",
            limits: .init(maxMessages: capacity, maxPayloadBytes: 2048,
                          messageLifetime: .greatestFiniteMagnitude, claimTimeout: 60, maxQuarantinedFiles: 8),
            overflowPolicy: .rejectNewest
        )
    }

    func enqueue(_ work: DeletionWork) throws {
        try mailbox.enqueue(work, id: work.stableID)
    }
}
