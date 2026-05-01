import Foundation
import CryptoKit
import Combine

/// Append-only, hash-chained audit log. Each event's `prevHash` is the previous event's `hash`,
/// giving you a tamper-evident chain that can be anchored externally.
@MainActor
final class AuditLog: ObservableObject {
    @Published private(set) var events: [AuditEvent] = []

    /// Genesis sentinel hash for the first link of the chain.
    private let genesis = "0000000000000000000000000000000000000000000000000000000000000000"

    func append(kind: AuditEvent.Kind,
                actor: String,
                summary: String,
                payload: [String: String] = [:]) {
        let prev = events.last?.hash ?? genesis
        let id = UUID()
        let ts = Date()
        let canonical = canonicalString(id: id,
                                        kind: kind,
                                        timestamp: ts,
                                        actor: actor,
                                        summary: summary,
                                        payload: payload,
                                        prevHash: prev)
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        let event = AuditEvent(
            id: id,
            kind: kind,
            timestamp: ts,
            actor: actor,
            summary: summary,
            payload: payload,
            prevHash: prev,
            hash: hash
        )
        events.append(event)
    }

    /// Verify the chain end-to-end. Returns the index of the first broken link or nil.
    func verifyChain() -> Int? {
        var prev = genesis
        for (idx, e) in events.enumerated() {
            if e.prevHash != prev { return idx }
            let canonical = canonicalString(id: e.id,
                                            kind: e.kind,
                                            timestamp: e.timestamp,
                                            actor: e.actor,
                                            summary: e.summary,
                                            payload: e.payload,
                                            prevHash: e.prevHash)
            let digest = SHA256.hash(data: Data(canonical.utf8))
            let h = digest.map { String(format: "%02x", $0) }.joined()
            if h != e.hash { return idx }
            prev = e.hash
        }
        return nil
    }

    private func canonicalString(id: UUID,
                                 kind: AuditEvent.Kind,
                                 timestamp: Date,
                                 actor: String,
                                 summary: String,
                                 payload: [String: String],
                                 prevHash: String) -> String {
        let sortedPayload = payload.keys.sorted()
            .map { "\"\($0)\":\"\(payload[$0]!)\"" }
            .joined(separator: ",")
        return "\(id.uuidString)|\(kind.rawValue)|\(Int(timestamp.timeIntervalSince1970 * 1000))|\(actor)|\(summary)|{\(sortedPayload)}|\(prevHash)"
    }
}
