import SwiftUI

/// Deep-dive view for a single Proposal: hero, pipeline visualization, rationale, snapshots,
/// intent/hash, and a pinned action bar to submit or discard.
struct ProposalDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let proposal: Proposal

    @State private var pipelineTrigger: Int = 0

    private var existingCase: ApprovalCase? {
        state.workflow.cases.first { $0.proposal.id == proposal.id }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    pipelineCard
                    rationaleCard
                    snapshotsRow
                    intentCard
                    Color.clear.frame(height: 92)   // bottom action bar spacing
                }
                .padding(16)
            }
            actionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .navigationTitle(proposal.intent.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Hero

    private var hero: some View {
        GlassCard(tint: Theme.Color.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(proposal.intent.symbol)
                                .font(Theme.Font.mono(34, weight: .bold))
                                .foregroundStyle(Theme.Color.textPrimary)
                            StatusPill(text: proposal.intent.side.rawValue,
                                       tone: proposal.intent.side == .buy ? .success : .warn)
                        }
                        Text(proposal.rationale.headline)
                            .font(Theme.Font.display(15, weight: .semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.usd(proposal.notional))
                            .font(Theme.Font.mono(16, weight: .semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("NOTIONAL")
                            .font(Theme.Font.mono(9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }

                HStack(spacing: 10) {
                    miniMetric("QTY", Fmt.qty(proposal.intent.qty))
                    miniMetric("LIMIT", proposal.intent.limitPrice.map { Fmt.usd($0, decimals: 2) } ?? "MKT")
                    miniMetric("TYPE", proposal.intent.orderType.rawValue)
                }

                HStack(spacing: 16) {
                    Meter(label: "Confidence",
                          value: proposal.confidence,
                          limit: 1.0,
                          tone: Theme.Color.accent,
                          format: { Fmt.pct($0, decimals: 0) })
                    Meter(label: "Expected α",
                          value: min(1.0, proposal.expectedAlphaBps / 100.0),
                          limit: 1.0,
                          tone: Theme.Color.accent2,
                          format: { _ in String(format: "%+.0f bps", proposal.expectedAlphaBps) })
                }
            }
        }
    }

    private func miniMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Font.mono(9, weight: .bold)).tracking(1.4).foregroundStyle(Theme.Color.textTertiary)
            Text(value).font(Theme.Font.mono(13, weight: .semibold)).foregroundStyle(Theme.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Color.surfaceStroke, lineWidth: 0.7))
    }

    // MARK: Pipeline

    private var pipelineCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: "Pipeline", subtitle: "Advisory → Deterministic")
                    Spacer()
                    Button {
                        pipelineTrigger += 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Replay pipeline")
                        }
                        .font(Theme.Font.body(11, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Color.accent.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Theme.Color.accent.opacity(0.5), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
                PipelineView(autoplay: true,
                             haltAt: existingCase?.state == .blocked ? .policy : nil,
                             trigger: $pipelineTrigger)
            }
        }
    }

    // MARK: Rationale

    private var rationaleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Rationale", subtitle: "Why this proposal")
                Text(proposal.rationale.headline)
                    .font(Theme.Font.display(18, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(proposal.rationale.thesis)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineSpacing(3)

                Text("SIGNALS")
                    .font(Theme.Font.mono(10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Color.textTertiary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                          spacing: 8) {
                    ForEach(proposal.rationale.signals) { sig in
                        signalChip(sig)
                    }
                }

                Text("KEY RISKS")
                    .font(Theme.Font.mono(10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Color.textTertiary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(proposal.rationale.risks, id: \.self) { r in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.Color.warn)
                                .padding(.top, 3)
                            Text(r)
                                .font(Theme.Font.body(12))
                                .foregroundStyle(Theme.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("CITATIONS")
                    .font(Theme.Font.mono(10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Color.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(proposal.rationale.citations, id: \.self) { c in
                        Text("• " + c)
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
            }
        }
    }

    private func signalChip(_ s: Rationale.Signal) -> some View {
        let tone: PillTone = {
            switch s.direction {
            case .bullish: return .success
            case .bearish: return .danger
            case .neutral: return .neutral
            }
        }()
        let icon: String = {
            switch s.direction {
            case .bullish: return "arrow.up.right"
            case .bearish: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tone.fg)
                .frame(width: 18, height: 18)
                .background(Circle().fill(tone.bg))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name)
                    .font(Theme.Font.body(11, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(s.value)
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(tone.fg)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tone.fg.opacity(0.3), lineWidth: 0.7))
    }

    // MARK: Snapshots

    private var snapshotsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            marketSnapshotCard
            riskSnapshotCard
        }
    }

    private var marketSnapshotCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MARKET SNAPSHOT")
                        .font(Theme.Font.mono(10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Color.accent)
                    Spacer()
                    StatusPill(text: proposal.market.fresh ? "Live" : "Stale",
                               tone: proposal.market.fresh ? .success : .warn,
                               pulses: proposal.market.fresh)
                }
                KVRow(key: "Last", value: Fmt.usd(proposal.market.last, decimals: 2))
                KVRow(key: "Bid / Ask",
                      value: "\(Fmt.usd(proposal.market.bid, decimals: 2)) / \(Fmt.usd(proposal.market.ask, decimals: 2))")
                KVRow(key: "Day Δ",
                      value: String(format: "%+.2f%%", proposal.market.dayChangePct * 100),
                      valueColor: proposal.market.dayChangePct >= 0 ? Theme.Color.success : Theme.Color.danger)
                KVRow(key: "Latency", value: String(format: "%.0f ms", proposal.market.venueLatencyMs))
                Sparkline(values: proposal.market.intraday,
                          tone: proposal.market.dayChangePct >= 0 ? Theme.Color.success : Theme.Color.warn)
                    .frame(height: 28)
            }
        }
    }

    private var riskSnapshotCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RISK SNAPSHOT")
                        .font(Theme.Font.mono(10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Color.accent2)
                    Spacer()
                    StatusPill(text: proposal.risk.fresh ? "Live" : "Stale",
                               tone: proposal.risk.fresh ? .success : .warn,
                               pulses: proposal.risk.fresh)
                }
                KVRow(key: "Used Exposure", value: Fmt.pct(proposal.risk.usedExposurePct))
                KVRow(key: "Available Cash", value: Fmt.usd(proposal.risk.availableCash))
                KVRow(key: "Drawdown",
                      value: Fmt.pct(proposal.risk.drawdownPct),
                      valueColor: proposal.risk.accountDrawdownOk ? Theme.Color.textPrimary : Theme.Color.danger)
                KVRow(key: "Kill Switch",
                      value: proposal.risk.killSwitchActive ? "ACTIVE" : "Clear",
                      valueColor: proposal.risk.killSwitchActive ? Theme.Color.danger : Theme.Color.success)
            }
        }
    }

    // MARK: Intent / hash

    private var intentCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Intent", subtitle: "Cryptographic identity")
                HStack(alignment: .top, spacing: 12) {
                    HashGlyph(hash: proposal.intent.intentHash(), size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INTENT HASH")
                            .font(Theme.Font.mono(9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(proposal.intent.intentHash())
                            .font(Theme.Font.mono(10))
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Rectangle().fill(Theme.Color.surfaceStroke).frame(height: 0.6)
                KVRow(key: "Model", value: proposal.modelId)
                KVRow(key: "Version", value: proposal.modelVersion)
                KVRow(key: "Idempotency Key", value: Fmt.shortHash(proposal.intent.idempotencyKey))
                KVRow(key: "Generated",
                      value: DateFormatter.localizedString(from: proposal.generatedAt, dateStyle: .none, timeStyle: .medium))
            }
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        GlassCard(padding: 12, tint: existingCase == nil ? Theme.Color.accent : Theme.Color.success) {
            if let kase = existingCase {
                HStack {
                    StatusPill(text: pillText(for: kase.state),
                               tone: pillTone(for: kase.state),
                               pulses: kase.state == .pending)
                    Spacer()
                    Text("View in Approvals →")
                        .font(Theme.Font.body(12, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                }
            } else {
                HStack(spacing: 10) {
                    NeonButton(title: "Discard",
                               icon: "trash",
                               tone: .neutral,
                               fill: false) {
                        dismiss()
                    }
                    NeonButton(title: "Submit for Approval",
                               icon: "paperplane.fill",
                               tone: .accent,
                               fill: true) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                            _ = state.submitForApproval(proposal: proposal)
                        }
                    }
                }
            }
        }
    }

    private func pillText(for s: ApprovalState) -> String {
        switch s {
        case .pending:   return "Pending Approval"
        case .approved:  return "Approved"
        case .rejected:  return "Rejected"
        case .expired:   return "Expired"
        case .executing: return "Executing"
        case .filled:    return "Filled"
        case .blocked:   return "Blocked"
        case .canceled:  return "Canceled"
        }
    }
    private func pillTone(for s: ApprovalState) -> PillTone {
        switch s {
        case .pending, .executing:    return .accent
        case .approved, .filled:      return .success
        case .rejected, .blocked:     return .danger
        case .expired, .canceled:     return .warn
        }
    }
}
