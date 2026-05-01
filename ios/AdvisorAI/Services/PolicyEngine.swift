import Foundation
import CryptoKit

/// OPA-style policy engine. Evaluates a deny-by-default set of rules around the deterministic
/// risk/freshness checks, and emits a versioned, hashed decision.
@MainActor
final class PolicyEngine {
    let policyVersion = "policy/2026.04.01"

    /// Mode + restricted list policies that wrap the RiskEngine output.
    func evaluate(intent: TradeIntent,
                  account: Account,
                  riskReasons: [PolicyReason],
                  mode: TradingMode,
                  notional: Double) -> PolicyDecision {

        var reasons = riskReasons

        // Mode gating
        let modeOk = mode != .research
        reasons.append(PolicyReason(
            rule: "ops.mode_allows_execution",
            description: "Current mode must permit execution.",
            passed: modeOk,
            detail: modeOk
                ? "Mode \(mode.label.uppercased()) allows order routing."
                : "Mode RESEARCH blocks all order routing — proposals are advisory only."
        ))

        // Capital cap by mode
        let capOk = notional <= mode.capitalCap
        reasons.append(PolicyReason(
            rule: "ops.mode_capital_cap",
            description: "Notional must fit current mode's capital cap.",
            passed: capOk,
            detail: "Notional \(Fmt.usd(notional)) vs \(mode.label) cap \(Fmt.usd(mode.capitalCap))."
        ))

        // Restricted list
        let restricted = account.restrictions.contains(intent.symbol)
        reasons.append(PolicyReason(
            rule: "compliance.restricted_list",
            description: "Symbol must not be on the account's restricted list.",
            passed: !restricted,
            detail: restricted
                ? "\(intent.symbol) is restricted on \(account.id)."
                : "\(intent.symbol) is not restricted on \(account.id)."
        ))

        // Asset class allowed
        let assetClass = Self.assetClass(for: intent.symbol)
        let assetOk = account.mandate.allowedAssetClasses.contains(assetClass)
        reasons.append(PolicyReason(
            rule: "mandate.asset_class",
            description: "Asset class must be permitted by mandate.",
            passed: assetOk,
            detail: "Asset class \(assetClass) \(assetOk ? "allowed" : "NOT allowed") under mandate \(account.mandate.strategy)."
        ))

        // Required approver count escalates with notional
        let approvers: Int = {
            if notional > 250_000 { return 2 }
            return 1
        }()
        reasons.append(PolicyReason(
            rule: "approval.required_approvers",
            description: "Determines how many approvers must sign.",
            passed: true,
            detail: "Notional \(Fmt.usd(notional)) requires \(approvers) approver\(approvers == 1 ? "" : "s")."
        ))

        let allow = reasons.allSatisfy { $0.passed }

        let canonical = canonicalize(reasons: reasons, version: policyVersion)
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        return PolicyDecision(
            allow: allow,
            policyVersion: policyVersion,
            policyHash: hash,
            requiredApprovers: approvers,
            reasons: reasons,
            evaluatedAt: Date()
        )
    }

    private func canonicalize(reasons: [PolicyReason], version: String) -> String {
        let parts = reasons.map { "\($0.rule)=\($0.passed ? "1" : "0")" }
        return "\(version)|" + parts.joined(separator: "|")
    }

    static func assetClass(for symbol: String) -> String {
        switch symbol {
        case "VTI", "IEF", "GLD": return "etf"
        default: return "us_equity"
        }
    }
}
