import SwiftUI

struct GovernanceView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var policyVersion: String = ""
    @State private var pendingMode: TradingMode? = nil
    @State private var showLiveConfirm = false
    @State private var showKillReasonSheet = false
    @State private var killReason: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if hSize == .regular {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 18)], spacing: 18) {
                            modeCard
                            killCard
                            feedCard
                            policyCard
                        }
                        architectureCard
                    } else {
                        modeCard
                        killCard
                        feedCard
                        policyCard
                        architectureCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if policyVersion.isEmpty {
                policyVersion = PolicyEngine().policyVersion
            }
        }
        .sheet(isPresented: $showLiveConfirm) {
            LiveConfirmSheet(
                cap: TradingMode.live.capitalCap,
                onConfirm: {
                    if let m = pendingMode { state.setMode(m) }
                    pendingMode = nil
                    showLiveConfirm = false
                },
                onCancel: {
                    pendingMode = nil
                    showLiveConfirm = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showKillReasonSheet) {
            KillReasonSheet(reason: $killReason) {
                let trimmed = killReason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                state.toggleKillSwitch(reason: trimmed)
                killReason = ""
                showKillReasonSheet = false
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOVERNANCE")
                .font(Theme.Font.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.Color.accent)
            Text("Governance")
                .font(Theme.Font.display(30, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Operational controls and policy posture.")
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mode card

    private var modeCard: some View {
        GlassCard(tint: modeTint(state.mode)) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Trading Mode",
                              subtitle: state.mode.label)
                HStack(alignment: .top, spacing: 14) {
                    Text(state.mode.label.uppercased())
                        .font(Theme.Font.mono(36, weight: .heavy))
                        .foregroundStyle(modeTint(state.mode))
                        .shadow(color: modeTint(state.mode).opacity(0.45), radius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capital cap")
                            .font(Theme.Font.body(11))
                            .foregroundStyle(Theme.Color.textSecondary)
                        Text(Fmt.usd(state.mode.capitalCap))
                            .font(Theme.Font.mono(18, weight: .bold))
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    Spacer()
                }
                Text(state.mode.description)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textSecondary)
                Divider().background(Theme.Color.surfaceStroke)
                HStack(spacing: 8) {
                    ForEach(TradingMode.allCases, id: \.self) { m in
                        modeChip(m)
                    }
                }
            }
        }
    }

    private func modeChip(_ m: TradingMode) -> some View {
        let selected = state.mode == m
        return Button {
            select(mode: m)
        } label: {
            VStack(spacing: 4) {
                Text(m.label)
                    .font(Theme.Font.body(12, weight: .bold))
                    .foregroundStyle(selected ? .black : Theme.Color.textPrimary)
                Text(Fmt.usd(m.capitalCap))
                    .font(Theme.Font.mono(10, weight: .semibold))
                    .foregroundStyle(selected ? Color.black.opacity(0.7) : Theme.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? modeTint(m) : Theme.Color.surfaceHi)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(modeTint(m).opacity(selected ? 0 : 0.5), lineWidth: 1)
            )
            .shadow(color: selected ? modeTint(m).opacity(0.45) : .clear, radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func select(mode m: TradingMode) {
        guard m != state.mode else { return }
        if m == .live {
            pendingMode = m
            showLiveConfirm = true
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                state.setMode(m)
            }
        }
    }

    private func modeTint(_ m: TradingMode) -> Color {
        switch m {
        case .research: return Theme.Color.textSecondary
        case .paper:    return Theme.Color.info
        case .canary:   return Theme.Color.warn
        case .live:     return Theme.Color.danger
        }
    }

    // MARK: - Kill switch card

    private var killCard: some View {
        let active = state.killSwitch.active
        return GlassCard(tint: active ? Theme.Color.danger : Theme.Color.success) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Kill Switch",
                              subtitle: active ? "ACTIVE" : "Clear")
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill((active ? Theme.Color.danger : Theme.Color.success).opacity(0.18))
                            .frame(width: 64, height: 64)
                        Circle()
                            .strokeBorder(active ? Theme.Color.danger : Theme.Color.success,
                                          lineWidth: 1.5)
                            .frame(width: 64, height: 64)
                        Image(systemName: active ? "exclamationmark.octagon.fill" : "bolt.shield.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(active ? Theme.Color.danger : Theme.Color.success)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(active ? "Halted" : "Operational")
                            .font(Theme.Font.display(20, weight: .bold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text(active
                             ? "OMS fails closed. New approvals will block at submission."
                             : "OMS accepts approved orders.")
                            .font(Theme.Font.body(11))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                }

                if active {
                    VStack(spacing: 8) {
                        KVRow(key: "Activated by", value: state.killSwitch.actor ?? "—")
                        KVRow(key: "Activated at",
                              value: state.killSwitch.activatedAt.map { shortDate($0) } ?? "—")
                        KVRow(key: "Reason", value: state.killSwitch.reason ?? "—")
                    }
                }

                NeonButton(
                    title: active ? "Clear Kill Switch" : "ACTIVATE KILL SWITCH",
                    icon: active ? "bolt.slash.fill" : "exclamationmark.octagon.fill",
                    tone: active ? .warn : .danger,
                    fill: !active
                ) {
                    if active {
                        state.toggleKillSwitch(reason: "Cleared by advisor")
                    } else {
                        showKillReasonSheet = true
                    }
                }

                Text("When active, OMS fails closed. All pending approvals will block at submission.")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Feed card

    private var feedCard: some View {
        let healthy = state.market.feedHealthy
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Market Feed",
                              subtitle: healthy ? "Healthy" : "Stale")
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill((healthy ? Theme.Color.success : Theme.Color.warn).opacity(0.16))
                            .frame(width: 56, height: 56)
                        Image(systemName: healthy ? "antenna.radiowaves.left.and.right" : "wifi.exclamationmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(healthy ? Theme.Color.success : Theme.Color.warn)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        StatusPill(text: healthy ? "Live" : "Stale",
                                   tone: healthy ? .success : .warn,
                                   pulses: healthy)
                        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                            let age = max(0, Date().timeIntervalSince(state.market.lastTick))
                            Text(healthy
                                 ? String(format: "Last tick %.0fs ago", age)
                                 : String(format: "Frozen %.0fs ago", age))
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    Spacer()
                }
                NeonButton(
                    title: healthy ? "Simulate Stale Feed" : "Restore Feed",
                    icon: healthy ? "wifi.slash" : "arrow.clockwise",
                    tone: healthy ? .warn : .success,
                    fill: false
                ) {
                    state.toggleFeed()
                }
                Text("Stale data trips data.market.fresh. Policy denies routing until restored.")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Policy rules card

    private struct RuleEntry {
        let rule: String
        let description: String
        let category: RuleCategory
    }

    private enum RuleCategory: String, CaseIterable {
        case data, ops, exec, risk, mandate, compliance, approval

        var label: String {
            switch self {
            case .data:       return "Data"
            case .ops:        return "Operations"
            case .exec:       return "Execution"
            case .risk:       return "Risk"
            case .mandate:    return "Mandate"
            case .compliance: return "Compliance"
            case .approval:   return "Approval"
            }
        }
        var icon: String {
            switch self {
            case .data:       return "antenna.radiowaves.left.and.right"
            case .ops:        return "gearshape.2.fill"
            case .exec:       return "paperplane.fill"
            case .risk:       return "shield.lefthalf.filled"
            case .mandate:    return "doc.text.fill"
            case .compliance: return "checkmark.shield.fill"
            case .approval:   return "person.2.badge.gearshape.fill"
            }
        }
        var tone: PillTone {
            switch self {
            case .data:       return .info
            case .ops:        return .warn
            case .exec:       return .accent
            case .risk:       return .danger
            case .mandate:    return .info
            case .compliance: return .success
            case .approval:   return .accent
            }
        }
    }

    private var allRules: [RuleEntry] {
        [
            RuleEntry(rule: "data.market.fresh",
                      description: "Market snapshot must be within TTL.",
                      category: .data),
            RuleEntry(rule: "data.risk.fresh",
                      description: "Risk snapshot must be within TTL.",
                      category: .data),
            RuleEntry(rule: "ops.kill_switch",
                      description: "Global kill switch must be inactive.",
                      category: .ops),
            RuleEntry(rule: "ops.mode_allows_execution",
                      description: "Current mode must permit order routing (research blocks all).",
                      category: .ops),
            RuleEntry(rule: "ops.mode_capital_cap",
                      description: "Notional must fit the active mode's capital cap.",
                      category: .ops),
            RuleEntry(rule: "exec.price_band",
                      description: "Limit price must sit within ±2% of last.",
                      category: .exec),
            RuleEntry(rule: "risk.cash_available",
                      description: "Buys must not exceed available cash.",
                      category: .risk),
            RuleEntry(rule: "risk.drawdown",
                      description: "Account drawdown must remain under mandate cap.",
                      category: .risk),
            RuleEntry(rule: "mandate.position_concentration",
                      description: "Position weight must respect mandate cap.",
                      category: .mandate),
            RuleEntry(rule: "mandate.asset_class",
                      description: "Asset class must be permitted by mandate.",
                      category: .mandate),
            RuleEntry(rule: "compliance.restricted_list",
                      description: "Symbol must not be on the account's restricted list.",
                      category: .compliance),
            RuleEntry(rule: "approval.required_approvers",
                      description: "Determines how many human approvers must sign.",
                      category: .approval)
        ]
    }

    private var policyCard: some View {
        let grouped = Dictionary(grouping: allRules, by: { $0.category })
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Policy Rules",
                              subtitle: "OPA-style deny-by-default")
                HStack {
                    StatusPill(text: policyVersion.isEmpty ? "policy/—" : policyVersion,
                               tone: .accent, icon: "lock.shield.fill")
                    Spacer()
                    Text("\(allRules.count) rules")
                        .font(Theme.Font.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                ForEach(RuleCategory.allCases, id: \.self) { cat in
                    if let rules = grouped[cat], !rules.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(rules, id: \.rule) { r in
                                    ruleRow(r)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: cat.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(cat.tone.fg)
                                Text(cat.label)
                                    .font(Theme.Font.body(13, weight: .semibold))
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                                Text("\(rules.count)")
                                    .font(Theme.Font.mono(11, weight: .semibold))
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                        }
                        .tint(Theme.Color.accent)
                    }
                }
                Text("AI may propose. Deterministic services decide. These rules are evaluated each submission.")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private func ruleRow(_ r: RuleEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: r.category.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(r.category.tone.fg)
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
            }
            Text(r.description)
                .font(Theme.Font.body(11))
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.leading, 16)
        }
    }

    // MARK: - Architecture card

    private var architectureCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Architecture",
                              subtitle: "Split-plane rule")
                HStack(alignment: .top, spacing: 12) {
                    planePanel(
                        title: "AI Advisory Plane",
                        tint: Theme.Color.accent2,
                        icon: "sparkles",
                        bullets: [
                            "Probabilistic models",
                            "Generates proposals + rationale",
                            "Cites signals and risks",
                            "Never reaches the venue directly"
                        ]
                    )
                    planePanel(
                        title: "Deterministic Execution Plane",
                        tint: Theme.Color.accent,
                        icon: "lock.shield.fill",
                        bullets: [
                            "Rules-based policy engine",
                            "HITL approval with signed token",
                            "Idempotent OMS + reconciliation",
                            "Hash-bound audit chain"
                        ]
                    )
                }
                Text("AI may propose and explain. Deterministic services decide and execute.")
                    .font(Theme.Font.mono(10, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }

    private func planePanel(title: String, tint: Color, icon: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(Theme.Font.body(12, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(tint).frame(width: 4, height: 4).padding(.top, 6)
                        Text(b)
                            .font(Theme.Font.body(11))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}

// MARK: - Live mode confirm sheet

private struct LiveConfirmSheet: View {
    let cap: Double
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.Gradient.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONFIRM LIVE MODE")
                        .font(Theme.Font.mono(11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.Color.danger)
                    Text("Switch to LIVE mode?")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                }

                GlassCard(tint: Theme.Color.danger) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Capital cap")
                                .font(Theme.Font.body(12))
                                .foregroundStyle(Theme.Color.textSecondary)
                            Spacer()
                            Text(Fmt.usd(cap))
                                .font(Theme.Font.mono(16, weight: .bold))
                                .foregroundStyle(Theme.Color.textPrimary)
                        }
                        Text("All controls remain active. Approvals, kill switch, drawdown, and concentration limits continue to apply.")
                            .font(Theme.Font.body(12))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }

                Spacer()
                NeonButton(title: "Confirm — Go Live", icon: "bolt.fill",
                           tone: .danger, fill: true) {
                    onConfirm()
                }
                NeonButton(title: "Cancel", tone: .neutral, fill: false) {
                    onCancel()
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Kill switch reason sheet

private struct KillReasonSheet: View {
    @Binding var reason: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Gradient.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ACTIVATE KILL SWITCH")
                        .font(Theme.Font.mono(11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.Color.danger)
                    Text("Halt all order routing")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("OMS will fail closed. Provide a reason for the audit trail.")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(Theme.Font.mono(10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Color.textSecondary)
                        TextField("e.g. Market dislocation — pause until reviewed",
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
                NeonButton(title: "Activate Kill Switch",
                           icon: "exclamationmark.octagon.fill",
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
