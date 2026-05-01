import Foundation

/// The AI advisory plane. Generates typed proposals and explanation packets. **Never** writes
/// to OMS or broker — outputs flow into the deterministic plane through bounded data structures.
@MainActor
final class AIAdvisorService {

    private let modelId = "advisor-copilot"
    private let modelVersion = "2026.04.r3"

    func proposalForRebalance(account: Account,
                              positions: [Position],
                              market: [String: MarketSnapshot],
                              risk: RiskSnapshot,
                              symbol: String,
                              side: TradeIntent.Side,
                              qty: Double,
                              orderType: TradeIntent.OrderType = .limit) -> Proposal? {
        guard let snap = market[symbol] else { return nil }
        let limit: Double? = orderType == .limit
            ? (side == .buy ? round100(snap.last * 1.0008) : round100(snap.last * 0.9992))
            : nil

        let intent = TradeIntent(
            id: UUID(),
            strategyId: account.mandate.strategy,
            accountId: account.id,
            symbol: symbol,
            side: side,
            qty: qty,
            orderType: orderType,
            limitPrice: limit,
            rationaleId: UUID(),
            idempotencyKey: UUID().uuidString,
            createdAt: Date()
        )

        let rationale = composeRationale(symbol: symbol,
                                         side: side,
                                         qty: qty,
                                         account: account,
                                         snap: snap,
                                         positions: positions)

        return Proposal(
            id: UUID(),
            intent: intent,
            market: snap,
            risk: risk,
            confidence: Double.random(in: 0.62...0.91),
            expectedAlphaBps: Double.random(in: 8...46),
            modelId: modelId,
            modelVersion: modelVersion,
            rationale: rationale,
            generatedAt: Date()
        )
    }

    private func composeRationale(symbol: String,
                                  side: TradeIntent.Side,
                                  qty: Double,
                                  account: Account,
                                  snap: MarketSnapshot,
                                  positions: [Position]) -> Rationale {
        let existing = positions.first { $0.account == account.id && $0.symbol == symbol }
        let weight = (existing?.marketValue ?? 0) / max(account.aum, 1)
        let targetWeight = side == .buy ? min(account.mandate.maxPositionPct, weight + 0.015) : max(0, weight - 0.015)

        let dir = side == .buy ? "increase" : "trim"
        let headline = "\(side == .buy ? "Add to" : "Trim") \(symbol) — \(dir) weight to \(String(format: "%.1f", targetWeight * 100))%"

        let thesisTemplates: [String] = [
            "Multi-factor model flags \(symbol) as overweighted by quality + momentum vs the strategy's neutral benchmark. Tightening the underweight by ~1.5% lowers tracking error against the benchmark while staying inside mandate caps.",
            "Recent earnings revisions on \(symbol) are in the top quintile of the universe. The optimizer's risk-adjusted return on incremental notional is favorable given current factor exposures and the account's available cash.",
            "Cross-asset signals show defensive rotation; \(symbol) screens favorably on liquidity and sector concentration. Rebalancing this leg first reduces realized vol contribution at the portfolio level.",
            "Drift from target weights has accumulated past the no-action band. The proposed \(side == .buy ? "buy" : "sell") moves the account back inside the target neighborhood with minimal turnover."
        ]
        let thesis = thesisTemplates.randomElement()!

        let signals: [Rationale.Signal] = [
            .init(name: "Momentum (12-1)", value: side == .buy ? "+2.1σ" : "-1.4σ", direction: side == .buy ? .bullish : .bearish),
            .init(name: "Quality factor",  value: "+1.6σ", direction: .bullish),
            .init(name: "Earnings revision", value: side == .buy ? "Top quintile" : "Bottom tercile", direction: side == .buy ? .bullish : .bearish),
            .init(name: "Implied vol skew", value: "Neutral", direction: .neutral),
            .init(name: "Cross-asset signal", value: "Mild risk-on", direction: .bullish)
        ]

        let risks: [String] = [
            "Single-name idiosyncratic risk; sized within mandate cap of \(String(format: "%.0f", account.mandate.maxPositionPct * 100))%.",
            "Execution slippage if intraday volume falls below 40% ADV — OMS can throttle participation.",
            "Model drift: shadow model variance under monitoring; re-evaluation on 3σ divergence."
        ]

        let citations: [String] = [
            "Strategy registry: \(account.mandate.strategy) v2026.03",
            "Factor library: alpha-factory/quality-momentum (commit 8a4f12e)",
            "Risk model: barra-equity-us-medium",
            "Universe: liquid_us_eq_top_1500"
        ]

        return Rationale(
            id: UUID(),
            headline: headline,
            thesis: thesis,
            signals: signals,
            risks: risks,
            citations: citations
        )
    }

    private func round100(_ v: Double) -> Double {
        (v * 100).rounded() / 100
    }
}
