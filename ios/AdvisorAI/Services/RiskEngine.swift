import Foundation

@MainActor
final class RiskEngine {
    func snapshot(for account: Account, positions: [Position], killSwitch: Bool) -> RiskSnapshot {
        let totalMV = positions.filter { $0.account == account.id }
            .reduce(0.0) { $0 + $1.marketValue }
        let used = account.aum > 0 ? max(0, totalMV / account.aum) : 0
        let drawdown = simulatedDrawdown(for: account.id)
        return RiskSnapshot(
            account: account.id,
            usedExposurePct: used,
            availableCash: account.cash,
            drawdownPct: drawdown,
            killSwitchActive: killSwitch,
            asOf: Date(),
            fresh: true,
            summary: "Account exposure \(String(format: "%.1f", used * 100))%; drawdown \(String(format: "%.2f", drawdown * 100))%."
        )
    }

    /// Pre-trade marketability + sizing + concentration check. Returns either an annotated approval
    /// or a list of failed checks.
    func evaluate(intent: TradeIntent,
                  account: Account,
                  positions: [Position],
                  market: MarketSnapshot,
                  risk: RiskSnapshot) -> [PolicyReason] {
        var out: [PolicyReason] = []

        // Freshness
        out.append(PolicyReason(
            rule: "data.market.fresh",
            description: "Market snapshot must be fresh.",
            passed: market.fresh,
            detail: market.fresh ? "Snapshot age within TTL." : "Stale market data — proposals frozen."
        ))
        out.append(PolicyReason(
            rule: "data.risk.fresh",
            description: "Risk snapshot must be fresh.",
            passed: risk.fresh,
            detail: risk.fresh ? "Risk snapshot age within TTL." : "Stale risk snapshot."
        ))

        // Kill switch
        out.append(PolicyReason(
            rule: "ops.kill_switch",
            description: "Global kill switch must be inactive.",
            passed: !risk.killSwitchActive,
            detail: risk.killSwitchActive ? "Kill switch ACTIVE — all new orders blocked." : "Kill switch clear."
        ))

        // Marketability — limit price within bands
        let band = 0.02
        let last = market.last
        let limitOk: Bool = {
            guard let lp = intent.limitPrice else { return true }
            let upper = last * (1 + band)
            let lower = last * (1 - band)
            return lp >= lower && lp <= upper
        }()
        out.append(PolicyReason(
            rule: "exec.price_band",
            description: "Limit price must sit within ±2% of last.",
            passed: limitOk,
            detail: limitOk
                ? "Limit price within ±2% band of \(Fmt.usd(last, decimals: 2))."
                : "Limit price outside ±2% band of \(Fmt.usd(last, decimals: 2))."
        ))

        // Notional vs cash (for buys)
        let notional = intent.qty * (intent.limitPrice ?? last)
        let cashOk = intent.side == .sell || notional <= account.cash * 1.0001
        out.append(PolicyReason(
            rule: "risk.cash_available",
            description: "Buys must not exceed available cash.",
            passed: cashOk,
            detail: cashOk
                ? "Notional \(Fmt.usd(notional)) within cash \(Fmt.usd(account.cash))."
                : "Notional \(Fmt.usd(notional)) exceeds cash \(Fmt.usd(account.cash))."
        ))

        // Position concentration
        let existing = positions.first { $0.account == account.id && $0.symbol == intent.symbol }
        let existingMV = existing?.marketValue ?? 0
        let projectedMV = existingMV + (intent.side == .buy ? notional : -notional)
        let concPct = account.aum > 0 ? abs(projectedMV) / account.aum : 0
        let concOk = concPct <= account.mandate.maxPositionPct
        out.append(PolicyReason(
            rule: "mandate.position_concentration",
            description: "Position weight must respect mandate cap.",
            passed: concOk,
            detail: "Projected weight \(String(format: "%.2f", concPct * 100))% vs cap \(String(format: "%.0f", account.mandate.maxPositionPct * 100))%."
        ))

        // Drawdown guardrail
        let ddOk = risk.drawdownPct < account.mandate.maxDrawdownPct
        out.append(PolicyReason(
            rule: "risk.drawdown",
            description: "Account drawdown must remain under mandate cap.",
            passed: ddOk,
            detail: "Drawdown \(String(format: "%.2f", risk.drawdownPct * 100))% vs cap \(String(format: "%.0f", account.mandate.maxDrawdownPct * 100))%."
        ))

        return out
    }

    private func simulatedDrawdown(for accountId: String) -> Double {
        // Stable per-account pseudo drawdown.
        let h = abs(accountId.hashValue) % 100
        return Double(h) / 100.0 * 0.07   // 0...7%
    }
}
