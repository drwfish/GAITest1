import Foundation
import CryptoKit
import Combine

/// Durable approval workflow. Models the wait-state, escalation, deadline expiry, and signed token
/// issuance that a Temporal-style runtime would handle in production.
@MainActor
final class ApprovalWorkflow: ObservableObject {
    @Published var cases: [ApprovalCase] = []

    /// Approval deadline window.
    private let approvalTTL: TimeInterval = 60 * 15
    /// Token validity once issued.
    private let tokenTTL: TimeInterval = 60 * 5

    private var sweeper: Timer?

    func start() {
        sweeper?.invalidate()
        sweeper = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireOverdue() }
        }
    }

    func stop() { sweeper?.invalidate(); sweeper = nil }

    func openCase(proposal: Proposal, policy: PolicyDecision) -> ApprovalCase {
        let now = Date()
        let kase = ApprovalCase(
            id: UUID(),
            proposal: proposal,
            policy: policy,
            state: policy.allow ? .pending : .blocked,
            approvers: [],
            createdAt: now,
            deadline: now.addingTimeInterval(approvalTTL),
            token: nil,
            execution: nil,
            blockReason: policy.allow ? nil : (policy.firstDenial?.detail ?? "Policy denied.")
        )
        cases.append(kase)
        return kase
    }

    func decide(caseId: UUID, approver: Approver) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        var k = cases[idx]
        guard k.state == .pending else { return }

        if approver.decision == .rejected {
            k.approvers.append(approver)
            k.state = .rejected
            cases[idx] = k
            return
        }

        if !k.approvers.contains(where: { $0.id == approver.id }) {
            k.approvers.append(approver)
        }

        let approved = k.approvers.filter { $0.decision == .approved }.count
        if approved >= k.policy.requiredApprovers {
            let token = issueToken(for: k)
            k.token = token
            k.state = .approved
        }

        cases[idx] = k
    }

    func attachExecution(caseId: UUID, execution: ExecutionResult, newState: ApprovalState) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        var k = cases[idx]
        k.execution = execution
        k.state = newState
        cases[idx] = k
    }

    func markExecuting(caseId: UUID) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        var k = cases[idx]
        k.state = .executing
        cases[idx] = k
    }

    private func expireOverdue() {
        let now = Date()
        for i in cases.indices {
            if cases[i].state == .pending && now > cases[i].deadline {
                cases[i].state = .expired
            }
        }
    }

    private func issueToken(for k: ApprovalCase) -> ApprovalToken {
        let now = Date()
        let id = UUID()
        let canonical = "\(id.uuidString)|\(k.proposal.intent.intentHash())|\(k.policy.policyHash)|\(Int(now.timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let sig = digest.map { String(format: "%02x", $0) }.joined()
        return ApprovalToken(
            approvalId: id,
            intentHash: k.proposal.intent.intentHash(),
            policyHash: k.policy.policyHash,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(tokenTTL),
            approvers: k.approvers,
            signature: sig
        )
    }
}
