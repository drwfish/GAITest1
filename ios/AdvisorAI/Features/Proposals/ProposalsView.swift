import SwiftUI

/// AI Proposals tab — the advisory plane.
/// Generates typed candidate proposals; humans review and submit them to the deterministic plane.
struct ProposalsView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedSymbol: String? = nil
    @State private var side: TradeIntent.Side = .buy
    @State private var generating: Bool = false

    private var sortedSymbols: [String] { state.market.snapshots.keys.sorted() }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        accountCard
                        generatorCard
                        proposalsList
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            if selectedSymbol == nil { selectedSymbol = sortedSymbols.first }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI PROPOSALS").font(Theme.Font.mono(11, weight: .bold)).tracking(2.4).foregroundStyle(Theme.Color.accent)
            Text("AI Proposals").font(Theme.Font.display(28, weight: .bold)).foregroundStyle(Theme.Color.textPrimary)
            Text("Advisory plane — typed candidates for human review.").font(Theme.Font.body(13)).foregroundStyle(Theme.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        if let acct = state.selectedAccount {
            GlassCard(padding: 14, tint: Theme.Color.accent2) {
                HStack(spacing: 12) {
                    Image(systemName: "briefcase.fill")
                        .foregroundStyle(Theme.Color.accent2)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Color.accent2.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(acct.name).font(Theme.Font.display(15, weight: .semibold)).foregroundStyle(Theme.Color.textPrimary)
                        Text("\(acct.id) · \(acct.mandate.strategy)").font(Theme.Font.mono(11)).foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.usd(acct.aum)).font(Theme.Font.mono(13, weight: .semibold)).foregroundStyle(Theme.Color.textPrimary)
                        Text("AUM").font(Theme.Font.mono(9, weight: .bold)).tracking(1.4).foregroundStyle(Theme.Color.textTertiary)
                    }
                }
            }
        }
    }

    private var generatorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Generate", subtitle: "Compose a proposal")
                labelText("SYMBOL")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sortedSymbols, id: \.self) { symbolPill($0) }
                    }
                    .padding(.vertical, 2)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        labelText("SIDE")
                        Picker("Side", selection: $side) {
                            Text("Buy").tag(TradeIntent.Side.buy)
                            Text("Sell").tag(TradeIntent.Side.sell)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    Spacer()
                }
                NeonButton(title: generating ? "Generating…" : "Generate Proposal",
                           icon: "sparkles", tone: .accent, fill: true,
                           disabled: selectedSymbol == nil || generating) { generate() }
            }
        }
    }

    private func labelText(_ s: String) -> some View {
        Text(s).font(Theme.Font.mono(10, weight: .bold)).tracking(1.6)
            .foregroundStyle(Theme.Color.textTertiary)
    }

    private func symbolPill(_ sym: String) -> some View {
        let selected = sym == selectedSymbol
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedSymbol = sym }
        } label: {
            HStack(spacing: 6) {
                Text(sym).font(Theme.Font.mono(13, weight: .bold))
                if let s = state.market.snapshots[sym] {
                    Text(String(format: "%+.1f%%", s.dayChangePct * 100))
                        .font(Theme.Font.mono(10, weight: .semibold))
                        .foregroundStyle(s.dayChangePct >= 0 ? Theme.Color.success : Theme.Color.danger)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? .black : Theme.Color.textPrimary)
            .background(Capsule().fill(selected ? Theme.Color.accent : Theme.Color.surfaceHi))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.Color.surfaceStroke, lineWidth: 0.8))
            .shadow(color: selected ? Theme.Color.accent.opacity(0.5) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func generate() {
        guard let sym = selectedSymbol else { return }
        generating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                _ = state.generateProposal(symbol: sym, side: side)
            }
            generating = false
        }
    }

    private var proposalsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Candidates",
                          subtitle: "\(state.proposals.count) proposal\(state.proposals.count == 1 ? "" : "s")")
            if state.proposals.isEmpty {
                emptyState
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(state.proposals.reversed()), id: \.id) { p in
                        ProposalCard(proposal: p)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.Color.accent)
                Text("No proposals yet.").font(Theme.Font.display(15, weight: .semibold)).foregroundStyle(Theme.Color.textPrimary)
                Text("Generate one to see the pipeline come alive.").font(Theme.Font.body(12)).foregroundStyle(Theme.Color.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }
}

// MARK: - Proposal card

private struct ProposalCard: View {
    @EnvironmentObject var state: AppState
    let proposal: Proposal

    private var existingCase: ApprovalCase? {
        state.workflow.cases.first { $0.proposal.id == proposal.id }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                topRow
                metricsRow
                Meter(label: "Confidence", value: proposal.confidence, limit: 1.0,
                      tone: Theme.Color.accent, format: { Fmt.pct($0, decimals: 0) })
                rationaleAndChart
                Rectangle().fill(Theme.Color.surfaceStroke).frame(height: 0.6)
                actionsRow
            }
        }
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(proposal.intent.symbol).font(Theme.Font.mono(26, weight: .bold)).foregroundStyle(Theme.Color.textPrimary)
                    StatusPill(text: proposal.intent.side.rawValue, tone: proposal.intent.side == .buy ? .success : .warn)
                }
                Text(proposal.market.summary).font(Theme.Font.body(11)).foregroundStyle(Theme.Color.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.usd(proposal.notional)).font(Theme.Font.mono(14, weight: .semibold)).foregroundStyle(Theme.Color.textPrimary)
                Text("NOTIONAL").font(Theme.Font.mono(9, weight: .bold)).tracking(1.4).foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metric("QTY", Fmt.qty(proposal.intent.qty))
            metric("LIMIT", proposal.intent.limitPrice.map { Fmt.usd($0, decimals: 2) } ?? "MKT")
            metric("ALPHA", String(format: "%+.0f bps", proposal.expectedAlphaBps),
                   color: proposal.expectedAlphaBps > 0 ? Theme.Color.success : Theme.Color.warn)
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = Theme.Color.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Font.mono(9, weight: .bold)).tracking(1.4).foregroundStyle(Theme.Color.textTertiary)
            Text(value).font(Theme.Font.mono(13, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Color.surfaceStroke, lineWidth: 0.7))
    }

    private var rationaleAndChart: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.rationale.headline).font(Theme.Font.body(13, weight: .semibold)).foregroundStyle(Theme.Color.textPrimary).lineLimit(2)
                Text(relativeTime(proposal.generatedAt)).font(Theme.Font.mono(10)).foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            Sparkline(values: proposal.market.intraday, tone: proposal.market.dayChangePct >= 0 ? Theme.Color.success : Theme.Color.warn).frame(width: 96, height: 36)
        }
    }

    @ViewBuilder
    private var actionsRow: some View {
        if let kase = existingCase {
            HStack {
                StatusPill(text: pillText(for: kase.state),
                           tone: pillTone(for: kase.state),
                           pulses: kase.state == .pending)
                Spacer()
                NavigationLink(destination: ProposalDetailView(proposal: proposal)) {
                    HStack(spacing: 4) {
                        Text("Inspect"); Image(systemName: "chevron.right")
                    }
                    .font(Theme.Font.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                }
            }
        } else {
            HStack(spacing: 10) {
                NeonButton(title: "Submit for Approval", icon: "paperplane.fill",
                           tone: .accent, fill: true) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                        _ = state.submitForApproval(proposal: proposal)
                    }
                }
                NavigationLink(destination: ProposalDetailView(proposal: proposal)) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass"); Text("Inspect")
                    }
                    .font(Theme.Font.body(14, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.Color.accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.Color.accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
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
        case .pending, .executing: return .accent
        case .approved, .filled:   return .success
        case .rejected, .blocked:  return .danger
        case .expired, .canceled:  return .warn
        }
    }
    private func relativeTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

