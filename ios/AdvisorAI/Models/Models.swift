import Foundation
import CryptoKit

// MARK: - Trading mode

enum TradingMode: String, CaseIterable, Codable {
    case research, paper, canary, live

    var label: String {
        switch self {
        case .research: return "Research"
        case .paper:    return "Paper"
        case .canary:   return "Canary"
        case .live:     return "Live"
        }
    }
    var description: String {
        switch self {
        case .research: return "Proposals only. Nothing routes to OMS."
        case .paper:    return "Full pipeline against simulated broker."
        case .canary:   return "Live capital, hard caps, supervised."
        case .live:     return "Production trading. All controls active."
        }
    }
    var capitalCap: Double {
        switch self {
        case .research: return 0
        case .paper:    return 10_000_000
        case .canary:   return 250_000
        case .live:     return 5_000_000
        }
    }
}

// MARK: - Account / mandate

struct Account: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let owner: String
    let aum: Double
    let cash: Double
    let mandate: Mandate
    let restrictions: [String]   // restricted tickers
}

struct Mandate: Codable, Hashable {
    let strategy: String
    let maxPositionPct: Double      // e.g. 0.08 = 8%
    let maxSectorPct: Double        // e.g. 0.30 = 30%
    let maxDrawdownPct: Double      // e.g. 0.12 = 12%
    let allowedAssetClasses: [String]
}

struct Position: Identifiable, Codable, Hashable {
    var id: String { "\(account)/\(symbol)" }
    let account: String
    let symbol: String
    let sector: String
    let qty: Double
    let avgCost: Double
    let mark: Double

    var marketValue: Double { qty * mark }
    var pnl: Double { qty * (mark - avgCost) }
    var pnlPct: Double { avgCost == 0 ? 0 : (mark - avgCost) / avgCost }
}

// MARK: - Snapshots

struct MarketSnapshot: Codable, Hashable {
    let symbol: String
    let bid: Double
    let ask: Double
    let last: Double
    let dayChangePct: Double
    let avgDailyVolume: Double
    let venueLatencyMs: Double
    let asOf: Date
    let fresh: Bool
    let summary: String
    let intraday: [Double]   // sparkline values
}

struct RiskSnapshot: Codable, Hashable {
    let account: String
    let usedExposurePct: Double
    let availableCash: Double
    let drawdownPct: Double
    let killSwitchActive: Bool
    let asOf: Date
    let fresh: Bool
    let summary: String

    var accountDrawdownOk: Bool { drawdownPct < 0.10 }
}

// MARK: - Trade intent

struct TradeIntent: Identifiable, Codable, Hashable {
    let id: UUID
    let strategyId: String
    let accountId: String
    let symbol: String
    let side: Side
    let qty: Double
    let orderType: OrderType
    let limitPrice: Double?
    let rationaleId: UUID
    let idempotencyKey: String
    let createdAt: Date

    enum Side: String, Codable, CaseIterable, Hashable {
        case buy = "BUY"
        case sell = "SELL"
    }
    enum OrderType: String, Codable, CaseIterable, Hashable {
        case market = "MARKET"
        case limit  = "LIMIT"
    }

    func canonicalDict() -> [String: String] {
        [
            "strategy_id":     strategyId,
            "account_id":      accountId,
            "symbol":          symbol,
            "side":            side.rawValue,
            "qty":             String(qty),
            "order_type":      orderType.rawValue,
            "limit_price":     limitPrice.map { String($0) } ?? "null",
            "rationale_id":    rationaleId.uuidString,
            "idempotency_key": idempotencyKey
        ]
    }

    func intentHash() -> String {
        let dict = canonicalDict()
        let sorted = dict.keys.sorted().map { "\"\($0)\":\"\(dict[$0]!)\"" }.joined(separator: ",")
        let canonical = "{\(sorted)}"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var notional: Double {
        (limitPrice ?? 0) * qty
    }
}

// MARK: - Proposal (what the AI plane produces)

struct Proposal: Identifiable, Codable, Hashable {
    let id: UUID
    let intent: TradeIntent
    let market: MarketSnapshot
    let risk: RiskSnapshot
    let confidence: Double          // 0...1
    let expectedAlphaBps: Double
    let modelId: String
    let modelVersion: String
    let rationale: Rationale
    let generatedAt: Date

    var notional: Double {
        intent.qty * (intent.limitPrice ?? market.last)
    }
}

struct Rationale: Codable, Hashable {
    let id: UUID
    let headline: String
    let thesis: String
    let signals: [Signal]
    let risks: [String]
    let citations: [String]

    struct Signal: Codable, Hashable, Identifiable {
        var id: String { name }
        let name: String
        let value: String
        let direction: Direction
        enum Direction: String, Codable { case bullish, bearish, neutral }
    }
}

// MARK: - Policy decision

struct PolicyDecision: Codable, Hashable {
    let allow: Bool
    let policyVersion: String
    let policyHash: String
    let requiredApprovers: Int
    let reasons: [PolicyReason]
    let evaluatedAt: Date

    var firstDenial: PolicyReason? { reasons.first { !$0.passed } }
}

struct PolicyReason: Codable, Hashable, Identifiable {
    var id: String { rule }
    let rule: String
    let description: String
    let passed: Bool
    let detail: String
}

// MARK: - Approval

struct ApprovalToken: Codable, Hashable {
    let approvalId: UUID
    let intentHash: String
    let policyHash: String
    let issuedAt: Date
    let expiresAt: Date
    let approvers: [Approver]
    let signature: String   // mock signature
}

struct Approver: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String
    let decidedAt: Date
    let decision: Decision
    enum Decision: String, Codable { case approved, rejected }
}

// MARK: - Approval workflow state

enum ApprovalState: String, Codable, Hashable {
    case pending
    case approved
    case rejected
    case expired
    case executing
    case filled
    case blocked
    case canceled
}

struct ApprovalCase: Identifiable, Hashable {
    let id: UUID
    let proposal: Proposal
    let policy: PolicyDecision
    var state: ApprovalState
    var approvers: [Approver]
    let createdAt: Date
    var deadline: Date
    var token: ApprovalToken?
    var execution: ExecutionResult?
    var blockReason: String?
}

// MARK: - Execution

struct ExecutionResult: Codable, Hashable {
    let brokerOrderId: String
    let clientOrderId: String
    let filledQty: Double
    let avgFillPrice: Double
    let slippageBps: Double
    let submittedAt: Date
    let acknowledgedAt: Date
    let venue: String
    let status: Status
    enum Status: String, Codable { case filled, partial, rejected }
}

// MARK: - Audit event

struct AuditEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: Kind
    let timestamp: Date
    let actor: String
    let summary: String
    let payload: [String: String]
    let prevHash: String
    let hash: String

    enum Kind: String, Codable, CaseIterable {
        case proposalGenerated   = "PROPOSAL_GENERATED"
        case policyEvaluated     = "POLICY_EVALUATED"
        case approvalRequested   = "APPROVAL_REQUESTED"
        case approvalGranted     = "APPROVAL_GRANTED"
        case approvalRejected    = "APPROVAL_REJECTED"
        case approvalExpired     = "APPROVAL_EXPIRED"
        case orderSubmitted      = "ORDER_SUBMITTED"
        case orderFilled         = "ORDER_FILLED"
        case executionBlocked    = "EXECUTION_BLOCKED"
        case killSwitchActivated = "KILL_SWITCH_ACTIVATED"
        case killSwitchCleared   = "KILL_SWITCH_CLEARED"
        case modeChanged         = "MODE_CHANGED"
        case reconciled          = "RECONCILED"

        var icon: String {
            switch self {
            case .proposalGenerated:   return "sparkles"
            case .policyEvaluated:     return "checkmark.shield"
            case .approvalRequested:   return "person.fill.questionmark"
            case .approvalGranted:     return "checkmark.seal.fill"
            case .approvalRejected:    return "xmark.seal.fill"
            case .approvalExpired:     return "clock.badge.xmark"
            case .orderSubmitted:      return "paperplane.fill"
            case .orderFilled:         return "checkmark.circle.fill"
            case .executionBlocked:    return "hand.raised.fill"
            case .killSwitchActivated: return "exclamationmark.octagon.fill"
            case .killSwitchCleared:   return "bolt.slash.fill"
            case .modeChanged:         return "arrow.triangle.2.circlepath"
            case .reconciled:          return "arrow.left.arrow.right"
            }
        }
        var tone: PillTone {
            switch self {
            case .proposalGenerated, .modeChanged, .reconciled:    return .info
            case .policyEvaluated, .approvalGranted, .orderFilled: return .success
            case .approvalRequested, .orderSubmitted:              return .accent
            case .approvalRejected, .approvalExpired,
                 .executionBlocked, .killSwitchActivated:          return .danger
            case .killSwitchCleared:                               return .warn
            }
        }
    }
}

// MARK: - Pipeline stage (drives the animated visualization)

enum PipelineStage: String, CaseIterable, Identifiable {
    case ingest, validate, signal, optimize, risk, policy, approval, oms, broker, reconcile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ingest:    return "Ingest"
        case .validate:  return "Validate"
        case .signal:    return "Signal"
        case .optimize:  return "Optimize"
        case .risk:      return "Risk"
        case .policy:    return "Policy"
        case .approval:  return "Approval"
        case .oms:       return "OMS"
        case .broker:    return "Broker"
        case .reconcile: return "Reconcile"
        }
    }
    var subtitle: String {
        switch self {
        case .ingest:    return "Market data + positions"
        case .validate:  return "Schema, freshness"
        case .signal:    return "Strategy outputs typed intent"
        case .optimize:  return "Sizing under mandate"
        case .risk:      return "Exposure, drawdown, slippage"
        case .policy:    return "OPA-style hard rules"
        case .approval:  return "Human-in-the-loop sign-off"
        case .oms:       return "Order manager (idempotent)"
        case .broker:    return "Adapter to venue"
        case .reconcile: return "Internal vs broker state"
        }
    }
    var icon: String {
        switch self {
        case .ingest:    return "antenna.radiowaves.left.and.right"
        case .validate:  return "checkmark.rectangle.stack"
        case .signal:    return "waveform.path.ecg"
        case .optimize:  return "chart.pie.fill"
        case .risk:      return "shield.lefthalf.filled"
        case .policy:    return "lock.shield.fill"
        case .approval:  return "person.2.badge.gearshape.fill"
        case .oms:       return "shippingbox.fill"
        case .broker:    return "network"
        case .reconcile: return "arrow.triangle.2.circlepath"
        }
    }
    /// Whether this stage belongs to the deterministic execution plane.
    var isDeterministic: Bool {
        switch self {
        case .signal: return false   // research / advisory
        default:      return true
        }
    }
}
