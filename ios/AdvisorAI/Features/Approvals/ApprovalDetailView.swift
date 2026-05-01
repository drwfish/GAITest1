import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ApprovalDetailView: View {
    @EnvironmentObject var state: AppState
    let approvalCase: ApprovalCase

    @State private var showRejectSheet = false
    @State private var showSecondApproverSheet = false
    @State private var rejectReason: String = ""
    @State private var copiedHash = false

    private var live: ApprovalCase {
        state.workflow.cases.first(where: { $0.id == approvalCase.id }) ?? approvalCase
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    intentCard
                    policyCard
                    statusCard
                    pipelineSummaryCard
                    if live.state == .blocked {
                        blockedBanner
                    }
                    Spacer().frame(height: live.state == .pending && live.policy.allow ? 110 : 24)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }

            if live.state == .pending && live.policy.allow {
                actionBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
        }
        .navigationTitle("Case \(String(live.id.uuidString.prefix(8)))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: "pipeline-\(live.id.uuidString)") {
                    Label("Pipeline", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
        }
        .navigationDestination(for: String.self) { tag in
            if tag.hasPrefix("pipeline-") {
                PipelineSummaryDetailView(kase: live)
            }
        }
        .sheet(isPresented: $showRejectSheet) {
            RejectSheet(reason: $rejectReason) {
                let trimmed = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                state.reject(caseId: live.id, as: MockData.advisor, reason: trimmed)
                rejectReason = ""
                showRejectSheet = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSecondApproverSheet) {
            SecondApproverSheet(
                exclude: live.approvers.map(\.id),
                onPick: { picked in
                    state.approve(caseId: live.id, as: picked)
                    showSecondApproverSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        let s = stateMeta(live.state)
        return GlassCard(tint: s.color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatusPill(text: live.proposal.intent.side.rawValue,
                               tone: live.proposal.intent.side == .buy ? .success : .danger)
                    Text(live.proposal.intent.symbol)
                        .font(Theme.Font.mono(28, weight: .heavy))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("× \(Fmt.qty(live.proposal.intent.qty))")
                        .font(Theme.Font.mono(15, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    StatusPill(text: state.mode.label, tone: modeTone(state.mode), icon: "gauge.with.dots.needle.bottom.50percent")
                    StatusPill(text: s.text, tone: s.tone, pulses: s.pulses)
                    Spacer()
                    Text(Fmt.usd(live.proposal.notional))
                        .font(Theme.Font.mono(16, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                }
                Text("Probabilistic AI proposed · deterministic policy decided · awaiting human approval.")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Intent

    private var intentCard: some View {
        let intent = live.proposal.intent
        let hash = intent.intentHash()
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Order Intent",
                              subtitle: "What the AI proposed")
                VStack(spacing: 8) {
                    KVRow(key: "Strategy", value: intent.strategyId)
                    KVRow(key: "Account", value: intent.accountId)
                    KVRow(key: "Symbol", value: intent.symbol)
                    KVRow(key: "Side", value: intent.side.rawValue,
                          valueColor: intent.side == .buy ? Theme.Color.success : Theme.Color.danger)
                    KVRow(key: "Quantity", value: Fmt.qty(intent.qty))
                    KVRow(key: "Order Type", value: intent.orderType.rawValue)
                    KVRow(key: "Limit Price",
                          value: intent.limitPrice.map { Fmt.usd($0, decimals: 2) } ?? "—")
                    KVRow(key: "Notional", value: Fmt.usd(live.proposal.notional))
                    KVRow(key: "Idempotency Key", value: Fmt.shortHash(intent.idempotencyKey))
                    KVRow(key: "Generated", value: shortDate(live.proposal.generatedAt))
                }
                Divider().background(Theme.Color.surfaceStroke)
                hashRow(label: "Intent Hash", hash: hash)
            }
        }
    }

    private func hashRow(label: String, hash: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(Theme.Font.mono(10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: 10) {
                HashGlyph(hash: hash, size: 28)
                Text(Fmt.shortHash(hash))
                    .font(Theme.Font.mono(12, weight: .medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                Button {
                    copyToPasteboard(hash)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedHash ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copiedHash ? "Copied" : "Copy")
                            .font(Theme.Font.mono(11, weight: .semibold))
                    }
                    .foregroundStyle(copiedHash ? Theme.Color.success : Theme.Color.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            (copiedHash ? Theme.Color.success : Theme.Color.accent).opacity(0.12)
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            (copiedHash ? Theme.Color.success : Theme.Color.accent).opacity(0.5),
                            lineWidth: 0.6
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            Text(hash)
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func copyToPasteboard(_ s: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = s
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copiedHash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut) { copiedHash = false }
        }
    }

    // MARK: - Policy

    private var policyCard: some View {
        let p = live.policy
        return GlassCard(tint: p.allow ? Theme.Color.success : Theme.Color.danger) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Policy Decision",
                              subtitle: p.allow ? "Allow" : "Deny")
                VStack(spacing: 8) {
                    KVRow(key: "Policy Version", value: p.policyVersion)
                    KVRow(key: "Required Approvers", value: "\(p.requiredApprovers)")
                    KVRow(key: "Evaluated", value: shortDate(p.evaluatedAt))
                }
                hashRow(label: "Policy Hash", hash: p.policyHash)

                Divider().background(Theme.Color.surfaceStroke)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(p.reasons) { r in
                        reasonRow(r)
                    }
                }
            }
        }
    }

    private func reasonRow(_ r: PolicyReason) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(r.passed ? Theme.Color.success : Theme.Color.danger)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(r.rule)
                        .font(Theme.Font.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.Color.surfaceHi)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Theme.Color.surfaceStroke, lineWidth: 0.5)
                        )
                    Text(r.description)
                        .font(Theme.Font.body(12, weight: r.passed ? .regular : .semibold))
                        .foregroundStyle(r.passed ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                        .lineLimit(2)
                }
                Text(r.detail)
                    .font(Theme.Font.body(11))
                    .foregroundStyle(r.passed ? Theme.Color.textTertiary : Theme.Color.danger.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Approval status

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Approval Status",
                              subtitle: subtitleForState(live.state))

                if live.state == .pending {
                    deadlineCountdown
                }

                approverProgress

                if !live.approvers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(live.approvers) { a in
                            approverRow(a)
                        }
                    }
                }

                if live.state == .approved, let token = live.token {
                    tokenBlock(token)
                }

                if (live.state == .executing || live.state == .filled || live.state == .blocked),
                   let exec = live.execution {
                    executionBlock(exec)
                }
            }
        }
    }

    private var deadlineCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let remaining = max(0, live.deadline.timeIntervalSinceNow)
            let total = max(1, live.deadline.timeIntervalSince(live.createdAt))
            let frac = max(0.0, min(1.0, remaining / total))
            let tone: Color = {
                if remaining < 30 { return Theme.Color.danger }
                if remaining < 120 { return Theme.Color.warn }
                return Theme.Color.accent
            }()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Deadline")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                    Text(formatRemaining(remaining))
                        .font(Theme.Font.mono(13, weight: .bold))
                        .foregroundStyle(tone)
                }
                .foregroundStyle(Theme.Color.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [tone, tone.opacity(0.55)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * frac, height: 6)
                            .animation(.linear(duration: 0.5), value: frac)
                    }
                }
                .frame(height: 6)
                Text("Approval is time-boxed and bound to this intent hash.")
                    .font(Theme.Font.body(10))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private var approverProgress: some View {
        let approved = live.approvers.filter { $0.decision == .approved }.count
        let required = live.policy.requiredApprovers
        let frac = required == 0 ? 1.0 : Double(approved) / Double(required)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Approvers")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text("\(approved) / \(required) signed")
                    .font(Theme.Font.mono(12, weight: .semibold))
                    .foregroundStyle(approved >= required ? Theme.Color.success : Theme.Color.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 5)
                    Capsule()
                        .fill(Theme.Gradient.successHorizon)
                        .frame(width: geo.size.width * min(1, frac), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    private func approverRow(_ a: Approver) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.Color.surfaceHi)
                .overlay(
                    Circle().strokeBorder(Theme.Color.accent.opacity(0.45), lineWidth: 1)
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Text(initials(a.name))
                        .font(Theme.Font.mono(11, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name)
                    .font(Theme.Font.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(a.role)
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                StatusPill(
                    text: a.decision == .approved ? "Approved" : "Rejected",
                    tone: a.decision == .approved ? .success : .danger,
                    icon: a.decision == .approved ? "checkmark" : "xmark"
                )
                Text(shortDate(a.decidedAt))
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func tokenBlock(_ token: ApprovalToken) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().background(Theme.Color.surfaceStroke)
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Color.success)
                Text("Approval Token Issued")
                    .font(Theme.Font.body(13, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
            }
            KVRow(key: "Approval ID", value: String(token.approvalId.uuidString.prefix(8)) + "…")
            hashRow(label: "Intent Hash Binding", hash: token.intentHash)
            hashRow(label: "Policy Hash Binding", hash: token.policyHash)
            KVRow(key: "Signature", value: Fmt.shortHash(token.signature))
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                let remaining = max(0, token.expiresAt.timeIntervalSinceNow)
                let tone: Color = remaining < 30 ? Theme.Color.danger
                                : remaining < 60 ? Theme.Color.warn
                                : Theme.Color.success
                HStack {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tone)
                    Text("Token expires")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                    Text(remaining > 0 ? formatRemaining(remaining) : "EXPIRED")
                        .font(Theme.Font.mono(12, weight: .bold))
                        .foregroundStyle(tone)
                }
            }
        }
    }

    private func executionBlock(_ exec: ExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().background(Theme.Color.surfaceStroke)
            HStack {
                Image(systemName: live.state == .blocked ? "hand.raised.fill" : "paperplane.fill")
                    .foregroundStyle(live.state == .blocked ? Theme.Color.danger : Theme.Color.info)
                Text(live.state == .blocked ? "Execution Blocked" : "Execution Result")
                    .font(Theme.Font.body(13, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
            }
            KVRow(key: "Broker Order ID", value: exec.brokerOrderId)
            VStack(alignment: .leading, spacing: 3) {
                KVRow(key: "Client Order ID", value: Fmt.shortHash(exec.clientOrderId))
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .bold))
                    Text("BINDS APPROVAL ↔ ORDER (= idempotency key)")
                        .font(Theme.Font.mono(9, weight: .semibold))
                        .tracking(0.4)
                }
                .foregroundStyle(Theme.Color.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.Color.accent.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Theme.Color.accent.opacity(0.4), lineWidth: 0.6))
            }
            KVRow(key: "Filled Qty", value: Fmt.qty(exec.filledQty))
            KVRow(key: "Avg Fill Price", value: Fmt.usd(exec.avgFillPrice, decimals: 2))
            KVRow(key: "Slippage", value: String(format: "%+.2f bps", exec.slippageBps),
                  valueColor: exec.slippageBps > 5 ? Theme.Color.warn : Theme.Color.textPrimary)
            KVRow(key: "Venue", value: exec.venue)
            let latency = max(0, exec.acknowledgedAt.timeIntervalSince(exec.submittedAt) * 1000)
            KVRow(key: "Latency", value: String(format: "%.0f ms", latency))
        }
    }

    // MARK: - Pipeline summary card

    private var pipelineSummaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Pipeline",
                              subtitle: "Gates crossed")
                let crossed = pipelineGates(for: live)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(crossed, id: \.title) { g in
                        HStack(spacing: 10) {
                            Image(systemName: g.passed ? "checkmark.circle.fill" :
                                              g.pending ? "circle.dotted" : "xmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(g.passed ? Theme.Color.success :
                                                 g.pending ? Theme.Color.textTertiary : Theme.Color.danger)
                            Text(g.title)
                                .font(Theme.Font.body(12, weight: .semibold))
                                .foregroundStyle(Theme.Color.textPrimary)
                            Spacer()
                            Text(g.subtitle)
                                .font(Theme.Font.mono(10))
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private struct GateRow {
        let title: String
        let subtitle: String
        let passed: Bool
        let pending: Bool
    }

    private func pipelineGates(for k: ApprovalCase) -> [GateRow] {
        var rows: [GateRow] = []
        rows.append(.init(title: "Signal", subtitle: "AI proposal generated", passed: true, pending: false))
        let riskOk = k.policy.reasons.filter {
            $0.rule.hasPrefix("data.") || $0.rule.hasPrefix("risk.") ||
            $0.rule == "exec.price_band" || $0.rule == "ops.kill_switch" ||
            $0.rule.hasPrefix("mandate.")
        }.allSatisfy { $0.passed }
        rows.append(.init(title: "Risk", subtitle: "Pre-trade checks", passed: riskOk, pending: false))
        rows.append(.init(title: "Policy", subtitle: k.policy.allow ? "ALLOW" : "DENY",
                          passed: k.policy.allow, pending: false))
        let approvalDone = k.state == .approved || k.state == .executing || k.state == .filled
        let approvalRejected = k.state == .rejected || k.state == .expired
        rows.append(.init(title: "Approval",
                          subtitle: approvalDone ? "Token issued"
                                  : approvalRejected ? "Halted"
                                  : k.state == .blocked ? "Blocked at policy" : "Awaiting",
                          passed: approvalDone,
                          pending: k.state == .pending))
        let omsOk = k.state == .filled
        rows.append(.init(title: "OMS / Broker",
                          subtitle: k.state == .filled ? "Filled"
                                  : k.state == .executing ? "Routing"
                                  : k.state == .blocked ? "Blocked" : "—",
                          passed: omsOk,
                          pending: k.state == .executing))
        return rows
    }

    // MARK: - Blocked banner

    private var blockedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Theme.Color.danger)
            Text("Execution blocked: \(live.blockReason ?? "policy denied")")
                .font(Theme.Font.body(13, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.danger.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Color.danger.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Action bar

    private var actionBar: some View {
        let needsSecond = live.policy.requiredApprovers > 1 &&
            live.approvers.filter { $0.decision == .approved }.count == 1
        return HStack(spacing: 10) {
            NeonButton(
                title: needsSecond ? "Add Second Approver" : "Approve",
                icon: needsSecond ? "person.2.fill" : "checkmark.seal.fill",
                tone: .success,
                fill: true
            ) {
                if needsSecond {
                    showSecondApproverSheet = true
                } else {
                    state.approve(caseId: live.id, as: MockData.advisor)
                }
            }
            NeonButton(
                title: "Reject",
                icon: "xmark.seal.fill",
                tone: .danger,
                fill: false
            ) {
                showRejectSheet = true
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.Color.surfaceStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 22, y: 14)
    }

    // MARK: - Helpers

    private func subtitleForState(_ s: ApprovalState) -> String {
        switch s {
        case .pending:   return "Awaiting human sign-off"
        case .approved:  return "Approved · token issued"
        case .rejected:  return "Rejected"
        case .expired:   return "Window expired"
        case .blocked:   return "Blocked at policy"
        case .executing: return "Submitted to OMS"
        case .filled:    return "Filled · reconciled"
        case .canceled:  return "Canceled"
        }
    }

    private func stateMeta(_ s: ApprovalState) -> (text: String, tone: PillTone, color: Color, pulses: Bool) {
        switch s {
        case .pending:   return ("Pending",   .accent,  Theme.Color.accent,  true)
        case .approved:  return ("Approved",  .success, Theme.Color.success, false)
        case .rejected:  return ("Rejected",  .danger,  Theme.Color.danger,  false)
        case .expired:   return ("Expired",   .warn,    Theme.Color.warn,    false)
        case .blocked:   return ("Blocked",   .danger,  Theme.Color.danger,  false)
        case .executing: return ("Executing", .info,    Theme.Color.info,    true)
        case .filled:    return ("Filled",    .success, Theme.Color.success, false)
        case .canceled:  return ("Canceled",  .neutral, Theme.Color.textSecondary, false)
        }
    }

    private func modeTone(_ m: TradingMode) -> PillTone {
        switch m {
        case .research: return .neutral
        case .paper:    return .info
        case .canary:   return .warn
        case .live:     return .danger
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? Character("?")) }.joined().uppercased()
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func formatRemaining(_ s: TimeInterval) -> String {
        if s <= 0 { return "00:00" }
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Reject sheet

private struct RejectSheet: View {
    @Binding var reason: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Gradient.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REJECT APPROVAL")
                        .font(Theme.Font.mono(11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.Color.danger)
                    Text("Reject this case")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Provide a reason — it will be written to the audit log.")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(Theme.Font.mono(10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Color.textSecondary)
                        TextField("e.g. Concentration too high near close",
                                  text: $reason, axis: .vertical)
                            .lineLimit(3...6)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Color.textPrimary)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.Color.surfaceHi)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.Color.surfaceStroke, lineWidth: 1)
                            )
                    }
                }

                Spacer()

                NeonButton(title: "Confirm Reject", icon: "xmark.seal.fill",
                           tone: .danger, fill: true,
                           disabled: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    onConfirm()
                }
                NeonButton(title: "Cancel", tone: .neutral, fill: false) {
                    dismiss()
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Second approver sheet

private struct SecondApproverSheet: View {
    let exclude: [String]
    let onPick: (Approver) -> Void
    @Environment(\.dismiss) private var dismiss

    private var available: [Approver] {
        MockData.allApprovers.filter { !exclude.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Theme.Gradient.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DUAL APPROVAL")
                        .font(Theme.Font.mono(11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.Color.accent)
                    Text("Select second approver")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Notional crosses the dual-control threshold. A different approver must co-sign.")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                if available.isEmpty {
                    GlassCard {
                        Text("No available co-approvers in this environment.")
                            .font(Theme.Font.body(13))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(available) { a in
                            Button {
                                onPick(a)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Theme.Color.surfaceHi)
                                        .overlay(Circle().strokeBorder(Theme.Color.accent.opacity(0.45), lineWidth: 1))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Text(initials(a.name))
                                                .font(Theme.Font.mono(12, weight: .bold))
                                                .foregroundStyle(Theme.Color.textPrimary)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.name)
                                            .font(Theme.Font.body(14, weight: .semibold))
                                            .foregroundStyle(Theme.Color.textPrimary)
                                        Text(a.role)
                                            .font(Theme.Font.body(11))
                                            .foregroundStyle(Theme.Color.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Theme.Color.accent)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.Color.surfaceHi)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Theme.Color.surfaceStroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
                NeonButton(title: "Cancel", tone: .neutral, fill: false) {
                    dismiss()
                }
            }
            .padding(18)
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? Character("?")) }.joined().uppercased()
    }
}

// MARK: - Pipeline summary detail destination

private struct PipelineSummaryDetailView: View {
    let kase: ApprovalCase

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Pipeline Trace",
                                      subtitle: "Stage-by-stage status")
                        Text("This case's path through the deterministic execution plane.")
                            .font(Theme.Font.body(12))
                            .foregroundStyle(Theme.Color.textSecondary)
                        ForEach(PipelineStage.allCases) { s in
                            HStack(spacing: 10) {
                                Image(systemName: s.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(Theme.Color.accent)
                                Text(s.title)
                                    .font(Theme.Font.body(13, weight: .semibold))
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                                Text(s.subtitle)
                                    .font(Theme.Font.mono(10))
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle("Pipeline")
        .navigationBarTitleDisplayMode(.inline)
    }
}
