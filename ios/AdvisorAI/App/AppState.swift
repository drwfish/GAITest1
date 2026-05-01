import Foundation
import Combine
import SwiftUI

/// The single observable orchestrator. All views read from here; all services are wired through.
/// This is the seam between the AI advisory plane (proposals) and the deterministic execution
/// plane (policy → approval → OMS → audit).
@MainActor
final class AppState: ObservableObject {

    // MARK: Services

    let market = MarketDataService()
    let advisor = AIAdvisorService()
    let policy = PolicyEngine()
    let risk = RiskEngine()
    let workflow = ApprovalWorkflow()
    let oms = OMS()
    let audit = AuditLog()
    let killSwitch = KillSwitch()

    // MARK: Published state

    @Published var accounts: [Account] = []
    @Published var positions: [Position] = []
    @Published var proposals: [Proposal] = []
    @Published var mode: TradingMode = .paper
    @Published var selectedAccountId: String? = nil
    @Published var lastNewProposal: Proposal? = nil
    /// Cross-tab routing slot. RootView observes this and switches tabs, then resets it to nil.
    @Published var requestedTab: AppTab? = nil

    // Combine wiring so the view layer reflects nested service updates.
    private var bag = Set<AnyCancellable>()

    init() {
        seed()
        wire()
    }

    private func seed() {
        accounts = MockData.accounts()
        positions = MockData.positions(for: accounts)
        selectedAccountId = accounts.first?.id
        market.seed(symbols: MockData.symbols)
        market.start()
        workflow.start()

        audit.append(kind: .modeChanged,
                     actor: "system",
                     summary: "Initialized in \(mode.label.uppercased()) mode.",
                     payload: ["mode": mode.rawValue, "capital_cap": String(Int(mode.capitalCap))])

        // Refresh marks once snapshots are seeded.
        rebuildMarks()
        // Generate a couple of initial proposals to seed the UI.
        generateProposal(symbol: "NVDA", side: .buy)
        generateProposal(symbol: "AAPL", side: .sell)
    }

    private func wire() {
        // When market ticks, refresh position marks for display.
        market.$snapshots
            .sink { [weak self] _ in self?.rebuildMarks() }
            .store(in: &bag)

        // Re-publish service-level changes so views observing AppState refresh.
        market.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        workflow.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        audit.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        killSwitch.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    private func rebuildMarks() {
        guard !positions.isEmpty else { return }
        var updated: [Position] = []
        updated.reserveCapacity(positions.count)
        for p in positions {
            let mark = market.snapshots[p.symbol]?.last ?? p.mark
            updated.append(Position(
                account: p.account,
                symbol: p.symbol,
                sector: p.sector,
                qty: p.qty,
                avgCost: p.avgCost,
                mark: mark
            ))
        }
        positions = updated
    }

    // MARK: Derived

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountId } ?? accounts.first
    }

    func positions(for accountId: String) -> [Position] {
        positions.filter { $0.account == accountId }
    }

    func aum(for accountId: String) -> Double {
        positions(for: accountId).reduce(0) { $0 + $1.marketValue }
    }

    func dayPnL(for accountId: String) -> Double {
        positions(for: accountId).reduce(0) { acc, p in
            let snap = market.snapshots[p.symbol]
            let chg = snap?.dayChangePct ?? 0
            return acc + p.marketValue * chg
        }
    }

    var openCases: [ApprovalCase] {
        workflow.cases.filter { $0.state == .pending }
    }

    var recentCases: [ApprovalCase] {
        Array(workflow.cases.suffix(20).reversed())
    }

    // MARK: Mode + kill switch

    func setMode(_ m: TradingMode) {
        guard m != mode else { return }
        let prev = mode
        mode = m
        audit.append(kind: .modeChanged,
                     actor: "advisor",
                     summary: "Mode changed \(prev.label.uppercased()) → \(m.label.uppercased()).",
                     payload: ["from": prev.rawValue, "to": m.rawValue])
    }

    func toggleKillSwitch(reason: String = "Manual halt by advisor") {
        if killSwitch.active {
            killSwitch.clear(actor: "advisor")
            audit.append(kind: .killSwitchCleared,
                         actor: "advisor",
                         summary: "Kill switch cleared.",
                         payload: [:])
        } else {
            killSwitch.activate(reason: reason, actor: "advisor")
            audit.append(kind: .killSwitchActivated,
                         actor: "advisor",
                         summary: "Kill switch activated: \(reason)",
                         payload: ["reason": reason])
        }
    }

    func toggleFeed() {
        if market.feedHealthy { market.degradeFeed() } else { market.restoreFeed() }
    }

    // MARK: Pipeline operations

    /// AI advisory plane → typed proposal. The proposal is **not** an order yet; it's a candidate
    /// the deterministic plane evaluates.
    @discardableResult
    func generateProposal(symbol: String, side: TradeIntent.Side, qty: Double? = nil) -> Proposal? {
        guard let account = selectedAccount else { return nil }
        let snap = market.snapshots[symbol] ?? MarketDataService.initialSnapshot(for: symbol)
        let riskSnap = risk.snapshot(for: account, positions: positions, killSwitch: killSwitch.active)

        let q = qty ?? defaultQty(for: symbol, account: account, snap: snap)

        guard let proposal = advisor.proposalForRebalance(
            account: account,
            positions: positions,
            market: market.snapshots,
            risk: riskSnap,
            symbol: symbol,
            side: side,
            qty: q
        ) else { return nil }

        proposals.append(proposal)
        lastNewProposal = proposal

        audit.append(
            kind: .proposalGenerated,
            actor: proposal.modelId,
            summary: "\(proposal.intent.side.rawValue) \(Int(proposal.intent.qty)) \(proposal.intent.symbol) @ \(Fmt.usd(proposal.intent.limitPrice ?? proposal.market.last, decimals: 2))",
            payload: [
                "intent_hash": proposal.intent.intentHash(),
                "model": proposal.modelId,
                "model_version": proposal.modelVersion,
                "confidence": String(format: "%.2f", proposal.confidence),
                "expected_alpha_bps": String(format: "%.0f", proposal.expectedAlphaBps)
            ]
        )

        return proposal
    }

    private func defaultQty(for symbol: String, account: Account, snap: MarketSnapshot) -> Double {
        let target = min(account.cash * 0.4, account.aum * 0.025)
        return max(1, (target / max(snap.last, 1)).rounded())
    }

    /// Submits a proposal to the deterministic plane: evaluates risk + policy and opens an
    /// approval case. Returns the case (whether or not policy passed).
    @discardableResult
    func submitForApproval(proposal: Proposal) -> ApprovalCase {
        guard let account = accounts.first(where: { $0.id == proposal.intent.accountId }) else {
            fatalError("Unknown account in proposal")
        }
        let riskSnap = risk.snapshot(for: account, positions: positions, killSwitch: killSwitch.active)
        let riskReasons = risk.evaluate(intent: proposal.intent,
                                        account: account,
                                        positions: positions,
                                        market: proposal.market,
                                        risk: riskSnap)
        let notional = proposal.intent.qty * (proposal.intent.limitPrice ?? proposal.market.last)
        let decision = policy.evaluate(intent: proposal.intent,
                                       account: account,
                                       riskReasons: riskReasons,
                                       mode: mode,
                                       notional: notional)

        audit.append(
            kind: .policyEvaluated,
            actor: "policy-engine",
            summary: "Policy \(decision.allow ? "allow" : "deny") for \(proposal.intent.symbol) (\(decision.reasons.filter { !$0.passed }.count) failures)",
            payload: [
                "intent_hash": proposal.intent.intentHash(),
                "policy_version": decision.policyVersion,
                "policy_hash": decision.policyHash,
                "allow": decision.allow ? "true" : "false"
            ]
        )

        let kase = workflow.openCase(proposal: proposal, policy: decision)

        if decision.allow {
            audit.append(
                kind: .approvalRequested,
                actor: "workflow",
                summary: "Approval requested for \(proposal.intent.symbol) (\(decision.requiredApprovers) approver\(decision.requiredApprovers == 1 ? "" : "s") required)",
                payload: [
                    "case_id": kase.id.uuidString,
                    "intent_hash": proposal.intent.intentHash(),
                    "deadline": ISO8601DateFormatter().string(from: kase.deadline)
                ]
            )
        } else {
            audit.append(
                kind: .executionBlocked,
                actor: "policy-engine",
                summary: "Blocked at policy: \(decision.firstDenial?.rule ?? "unknown")",
                payload: [
                    "case_id": kase.id.uuidString,
                    "intent_hash": proposal.intent.intentHash(),
                    "reason": decision.firstDenial?.detail ?? "—"
                ]
            )
        }

        return kase
    }

    /// HITL decision on a case.
    func approve(caseId: UUID, as approverTemplate: Approver) {
        let approver = Approver(
            id: approverTemplate.id,
            name: approverTemplate.name,
            role: approverTemplate.role,
            decidedAt: Date(),
            decision: .approved
        )
        workflow.decide(caseId: caseId, approver: approver)

        guard let kase = workflow.cases.first(where: { $0.id == caseId }) else { return }
        if kase.state == .approved {
            audit.append(
                kind: .approvalGranted,
                actor: approver.id,
                summary: "Approval granted by \(kase.approvers.map(\.name).joined(separator: ", "))",
                payload: [
                    "case_id": caseId.uuidString,
                    "intent_hash": kase.proposal.intent.intentHash(),
                    "token_id": kase.token?.approvalId.uuidString ?? "—"
                ]
            )
            // Auto-execute approved cases.
            execute(caseId: caseId)
        } else {
            audit.append(
                kind: .approvalRequested,
                actor: approver.id,
                summary: "Partial approval (\(kase.approvers.filter { $0.decision == .approved }.count)/\(kase.policy.requiredApprovers)) by \(approver.name)",
                payload: [
                    "case_id": caseId.uuidString,
                    "approver": approver.id
                ]
            )
        }
    }

    func reject(caseId: UUID, as approverTemplate: Approver, reason: String) {
        let approver = Approver(
            id: approverTemplate.id,
            name: approverTemplate.name,
            role: approverTemplate.role,
            decidedAt: Date(),
            decision: .rejected
        )
        workflow.decide(caseId: caseId, approver: approver)
        guard let kase = workflow.cases.first(where: { $0.id == caseId }) else { return }
        audit.append(
            kind: .approvalRejected,
            actor: approver.id,
            summary: "Rejected by \(approver.name): \(reason)",
            payload: [
                "case_id": caseId.uuidString,
                "intent_hash": kase.proposal.intent.intentHash(),
                "reason": reason
            ]
        )
    }

    private func execute(caseId: UUID) {
        guard let kase = workflow.cases.first(where: { $0.id == caseId }),
              let token = kase.token,
              let account = accounts.first(where: { $0.id == kase.proposal.intent.accountId })
        else { return }

        workflow.markExecuting(caseId: caseId)
        let riskSnap = risk.snapshot(for: account, positions: positions, killSwitch: killSwitch.active)
        let result = oms.submit(intent: kase.proposal.intent,
                                approval: token,
                                market: kase.proposal.market,
                                risk: riskSnap)

        switch result {
        case .submitted(let exec):
            workflow.attachExecution(caseId: caseId, execution: exec, newState: .filled)
            audit.append(
                kind: .orderSubmitted,
                actor: "oms",
                summary: "Submitted \(kase.proposal.intent.side.rawValue) \(Int(kase.proposal.intent.qty)) \(kase.proposal.intent.symbol)",
                payload: [
                    "intent_hash": kase.proposal.intent.intentHash(),
                    "broker_order_id": exec.brokerOrderId,
                    "client_order_id": exec.clientOrderId,
                    "approval_id": token.approvalId.uuidString
                ]
            )
            audit.append(
                kind: .orderFilled,
                actor: "broker-sim",
                summary: "Filled \(Int(exec.filledQty)) \(kase.proposal.intent.symbol) @ \(Fmt.usd(exec.avgFillPrice, decimals: 2)) (\(String(format: "%+.1f", exec.slippageBps)) bps)",
                payload: [
                    "broker_order_id": exec.brokerOrderId,
                    "venue": exec.venue,
                    "slippage_bps": String(format: "%.2f", exec.slippageBps)
                ]
            )
            applyFillToPositions(intent: kase.proposal.intent, exec: exec)
            audit.append(
                kind: .reconciled,
                actor: "reconciler",
                summary: "Internal vs broker state matches.",
                payload: ["broker_order_id": exec.brokerOrderId]
            )
        case .blocked(let reason):
            workflow.attachExecution(caseId: caseId,
                                     execution: ExecutionResult(
                                        brokerOrderId: "—",
                                        clientOrderId: kase.proposal.intent.idempotencyKey,
                                        filledQty: 0,
                                        avgFillPrice: 0,
                                        slippageBps: 0,
                                        submittedAt: Date(),
                                        acknowledgedAt: Date(),
                                        venue: "—",
                                        status: .rejected),
                                     newState: .blocked)
            audit.append(
                kind: .executionBlocked,
                actor: "oms",
                summary: "OMS blocked submission: \(reason)",
                payload: [
                    "intent_hash": kase.proposal.intent.intentHash(),
                    "reason": reason
                ]
            )
        }
    }

    private func applyFillToPositions(intent: TradeIntent, exec: ExecutionResult) {
        let signedQty = intent.side == .buy ? exec.filledQty : -exec.filledQty
        if let idx = positions.firstIndex(where: { $0.account == intent.accountId && $0.symbol == intent.symbol }) {
            let p = positions[idx]
            let newQty = p.qty + signedQty
            let newAvg = newQty == 0 ? p.avgCost : ((p.avgCost * p.qty + exec.avgFillPrice * signedQty) / newQty)
            positions[idx] = Position(
                account: p.account,
                symbol: p.symbol,
                sector: p.sector,
                qty: newQty,
                avgCost: max(0, newAvg),
                mark: market.snapshots[p.symbol]?.last ?? p.mark
            )
        } else if intent.side == .buy {
            positions.append(Position(
                account: intent.accountId,
                symbol: intent.symbol,
                sector: MockData.sectors(for: intent.symbol),
                qty: exec.filledQty,
                avgCost: exec.avgFillPrice,
                mark: market.snapshots[intent.symbol]?.last ?? exec.avgFillPrice
            ))
        }
    }
}
