import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var appeared = false
    @State private var aumDisplay: Double = 0
    @State private var pnlDisplay: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    accountPicker
                    heroCard
                    marketStrip
                    twoColumnSection
                    activityFeed
                    quickActions
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .navigationTitle("Mission Control")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { runAppearAnimations() }
            .onChange(of: state.selectedAccountId) { _, _ in runAppearAnimations() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION CONTROL")
                .font(Theme.Font.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.Color.accent)
            Text("Advisor Console")
                .font(Theme.Font.display(28, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Live oversight of advisory and execution planes.")
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    // MARK: - Account picker

    private var accountPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.accounts) { acct in
                    let selected = acct.id == state.selectedAccountId
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            state.selectedAccountId = acct.id
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acct.name)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(selected ? Color.black : Theme.Color.textPrimary)
                            Text(acct.id)
                                .font(Theme.Font.mono(10))
                                .foregroundStyle(selected ? Color.black.opacity(0.6) : Theme.Color.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selected ? Theme.Color.accent : Theme.Color.surface)
                        )
                        .overlay(
                            Capsule().strokeBorder(selected ? Color.clear : Theme.Color.surfaceStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.selectedAccount?.name ?? "—")
                            .font(Theme.Font.display(22, weight: .bold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text(state.selectedAccount?.owner ?? "—")
                            .font(Theme.Font.body(12))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    StatusPill(text: state.mode.label, tone: modeTone, icon: "circle.fill", pulses: state.mode == .live)
                }

                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUM")
                            .font(Theme.Font.mono(10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(Fmt.usd(aumDisplay, decimals: 0))
                            .font(Theme.Font.mono(26, weight: .bold))
                            .foregroundStyle(Theme.Color.textPrimary)
                            .contentTransition(.numericText())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAY P&L")
                            .font(Theme.Font.mono(10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text((pnlDisplay >= 0 ? "+" : "") + Fmt.usd(pnlDisplay, decimals: 0))
                            .font(Theme.Font.mono(20, weight: .semibold))
                            .foregroundStyle(pnlDisplay >= 0 ? Theme.Color.success : Theme.Color.danger)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CASH")
                            .font(Theme.Font.mono(10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(Fmt.usd(state.selectedAccount?.cash ?? 0, decimals: 0))
                            .font(Theme.Font.mono(16, weight: .semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                }

                Divider().overlay(Theme.Color.surfaceStroke)

                HStack(spacing: 8) {
                    let chainOk = state.audit.verifyChain() == nil
                    StatusPill(
                        text: state.market.feedHealthy ? "Feed Healthy" : "Feed Degraded",
                        tone: state.market.feedHealthy ? .success : .warn,
                        pulses: state.market.feedHealthy
                    )
                    StatusPill(
                        text: state.killSwitch.active ? "Kill Switch ON" : "Kill Switch Off",
                        tone: state.killSwitch.active ? .danger : .neutral,
                        icon: state.killSwitch.active ? "exclamationmark.octagon.fill" : "bolt.slash"
                    )
                    StatusPill(
                        text: chainOk ? "Chain OK" : "Chain Broken",
                        tone: chainOk ? .success : .danger,
                        icon: "link"
                    )
                    Spacer()
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private var modeTone: PillTone {
        switch state.mode {
        case .research: return .info
        case .paper:    return .accent
        case .canary:   return .warn
        case .live:     return .success
        }
    }

    // MARK: - Market strip

    private var marketStrip: some View {
        let symbols = Array(state.market.snapshots.values
            .sorted { $0.symbol < $1.symbol }
            .prefix(6))
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Market", subtitle: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(symbols, id: \.symbol) { s in
                            marketTile(s)
                        }
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
    }

    private func marketTile(_ s: MarketSnapshot) -> some View {
        let positive = s.dayChangePct >= 0
        let tone = positive ? Theme.Color.success : Theme.Color.danger
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.symbol)
                    .font(Theme.Font.mono(12, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tone)
            }
            Text(Fmt.usd(s.last, decimals: 2))
                .font(Theme.Font.mono(14, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Text((positive ? "+" : "") + String(format: "%.2f%%", s.dayChangePct * 100))
                .font(Theme.Font.mono(11, weight: .medium))
                .foregroundStyle(tone)
            Sparkline(values: s.intraday, tone: tone)
                .frame(height: 40)
        }
        .padding(10)
        .frame(width: 132)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.surfaceHi)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Color.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Two column section (holdings + risk)

    private var twoColumnSection: some View {
        Group {
            if hSize == .regular {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18)], spacing: 18) {
                    holdingsCard
                    riskCard
                }
            } else {
                VStack(spacing: 18) {
                    holdingsCard
                    riskCard
                }
            }
        }
    }

    private var holdingsCard: some View {
        let positions = state.positions(for: state.selectedAccountId ?? "")
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Holdings", subtitle: nil,
                              trailing: AnyView(Text("\(positions.count) positions")
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Color.textTertiary)))

                HStack {
                    Text("Symbol").frame(width: 70, alignment: .leading)
                    Text("Qty").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Mark").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Value").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("P&L%").frame(width: 64, alignment: .trailing)
                    Spacer().frame(width: 12)
                }
                .font(Theme.Font.mono(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.textTertiary)

                if positions.isEmpty {
                    Text("No positions in this account.")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 6) {
                        ForEach(positions) { p in
                            holdingRow(p)
                        }
                    }
                }
            }
        }
    }

    private func holdingRow(_ p: Position) -> some View {
        let tone: Color = p.pnlPct >= 0 ? Theme.Color.success : Theme.Color.danger
        return HStack {
            Text(p.symbol)
                .font(Theme.Font.mono(12, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 70, alignment: .leading)
            Text(Fmt.qty(p.qty))
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(Fmt.usd(p.mark, decimals: 2))
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(Fmt.usd(p.marketValue, decimals: 0))
                .font(Theme.Font.mono(12, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text((p.pnlPct >= 0 ? "+" : "") + String(format: "%.1f%%", p.pnlPct * 100))
                .font(Theme.Font.mono(12, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }

    private var riskCard: some View {
        let positions = state.positions(for: state.selectedAccountId ?? "")
        let aum = state.aum(for: state.selectedAccountId ?? "")
        let cash = state.selectedAccount?.cash ?? 0
        let totalCapital = max(1, aum + cash)
        let exposureUsed = aum / totalCapital
        let cashBuffer   = cash / totalCapital
        let drawdown = computeDrawdown(positions: positions)
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Risk", subtitle: nil)
                Meter(label: "Exposure used", value: exposureUsed, limit: 1.0,
                      tone: Theme.Color.accent)
                Meter(label: "Drawdown", value: drawdown, limit: 0.10,
                      tone: Theme.Color.warn,
                      format: { String(format: "%.2f%%", $0 * 100) })
                Meter(label: "Cash buffer", value: cashBuffer, limit: 1.0,
                      tone: Theme.Color.accent2)
            }
        }
    }

    private func computeDrawdown(positions: [Position]) -> Double {
        let totalPnl = positions.reduce(0) { $0 + $1.pnl }
        let basis = max(1, positions.reduce(0) { $0 + $1.qty * $1.avgCost })
        let dd = -min(0, totalPnl) / basis
        return min(max(dd, 0), 1)
    }

    // MARK: - Activity feed

    private var activityFeed: some View {
        let recent = Array(state.audit.events.suffix(6).reversed())
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Activity", subtitle: nil)
                if recent.isEmpty {
                    Text("No activity yet.")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(recent) { ev in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: ev.kind.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(ev.kind.tone.fg)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        Circle().fill(ev.kind.tone.fg.opacity(0.14))
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.summary)
                                        .font(Theme.Font.body(13))
                                        .foregroundStyle(Theme.Color.textPrimary)
                                        .lineLimit(2)
                                    Text(ev.actor + " · " + relative(ev.timestamp))
                                        .font(Theme.Font.mono(10))
                                        .foregroundStyle(Theme.Color.textTertiary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        let buttons = HStack(spacing: 10) {
            NeonButton(title: "Run Rebalance Scan", icon: "sparkles", tone: .accent, fill: true) {
                Task { @MainActor in
                    let pool = ["NVDA", "AAPL", "MSFT", "AMZN", "GOOGL", "META", "TSLA"]
                    let picks = pool.shuffled().prefix(2)
                    for sym in picks {
                        let side: TradeIntent.Side = Bool.random() ? .buy : .sell
                        _ = state.generateProposal(symbol: sym, side: side)
                    }
                }
            }
            NeonButton(title: "Toggle Feed", icon: "antenna.radiowaves.left.and.right", tone: .info, fill: false) {
                state.toggleFeed()
            }
            NeonButton(title: "Open Approvals", icon: "person.2.badge.gearshape.fill", tone: .accent, fill: false) {
                state.requestedTab = .approvals
            }
        }
        return buttons
    }

    // MARK: - Animations

    private func runAppearAnimations() {
        appeared = false
        aumDisplay = 0
        pnlDisplay = 0
        let targetAum = state.aum(for: state.selectedAccountId ?? "")
        let targetPnl = state.dayPnL(for: state.selectedAccountId ?? "")
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            appeared = true
        }
        withAnimation(.easeOut(duration: 0.9)) {
            aumDisplay = targetAum
            pnlDisplay = targetPnl
        }
    }
}
