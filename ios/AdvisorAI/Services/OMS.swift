import Foundation
import CryptoKit

/// Order Management System. Mirrors the safe_execute pseudocode from the architecture document:
/// fail-closed on missing/expired/mismatched approval, idempotent on submission, fresh-data check.
@MainActor
final class OMS {
    private(set) var seenIdempotencyKeys: Set<String> = []

    enum SubmitResult {
        case submitted(ExecutionResult)
        case blocked(reason: String)
    }

    func submit(intent: TradeIntent,
                approval: ApprovalToken,
                market: MarketSnapshot,
                risk: RiskSnapshot) -> SubmitResult {

        // 1. Approval must bind to this exact intent.
        guard approval.intentHash == intent.intentHash() else {
            return .blocked(reason: "Approval/intent hash mismatch.")
        }
        // 2. Approval must be unexpired.
        guard approval.expiresAt > Date() else {
            return .blocked(reason: "Approval token expired.")
        }
        // 3. Approval signature must verify (mock: recompute).
        guard verify(token: approval) else {
            return .blocked(reason: "Approval signature invalid.")
        }
        // 4. Idempotency.
        guard !seenIdempotencyKeys.contains(intent.idempotencyKey) else {
            return .blocked(reason: "Duplicate idempotency key.")
        }
        // 5. Freshness checks.
        guard market.fresh else { return .blocked(reason: "Stale market snapshot.") }
        guard risk.fresh else   { return .blocked(reason: "Stale risk snapshot.") }
        // 6. Kill switch + drawdown re-check.
        if risk.killSwitchActive { return .blocked(reason: "Kill switch active.") }
        guard risk.accountDrawdownOk else { return .blocked(reason: "Drawdown guardrail triggered.") }

        // OK to submit.
        seenIdempotencyKeys.insert(intent.idempotencyKey)

        // Apply price band sizing — if limit set, we use it; else mark.
        let last = market.last
        let executionPx = intent.limitPrice ?? last
        // Simulate small slippage (mock execution).
        let slipBps = Double.random(in: -2...6)
        let fillPx = executionPx * (1 + (intent.side == .buy ? slipBps : -slipBps) / 10_000)

        let now = Date()
        let result = ExecutionResult(
            brokerOrderId: "BRK-\(UUID().uuidString.prefix(10))",
            clientOrderId: intent.idempotencyKey,
            filledQty: intent.qty,
            avgFillPrice: round2(fillPx),
            slippageBps: round2(slipBps),
            submittedAt: now,
            acknowledgedAt: now.addingTimeInterval(0.18),
            venue: "SIM-VENUE",
            status: .filled
        )
        return .submitted(result)
    }

    private func verify(token: ApprovalToken) -> Bool {
        let canonical = "\(token.approvalId.uuidString)|\(token.intentHash)|\(token.policyHash)|\(Int(token.issuedAt.timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let sig = digest.map { String(format: "%02x", $0) }.joined()
        return sig == token.signature
    }

    private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
