import SwiftUI

struct AuditTrailView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedFilter: FilterChoice = .all
    @State private var expanded: Set<UUID> = []
    @State private var toastText: String? = nil
    @State private var toastTone: PillTone = .success

    private enum FilterChoice: Hashable {
        case all
        case kind(AuditEvent.Kind)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        chainCard
                        filterChips
                        eventsList
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                }

                bottomBar

                if let toastText {
                    toast(text: toastText, tone: toastTone)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Audit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        let count = state.audit.events.count
        let broken = state.audit.verifyChain() != nil
        return VStack(alignment: .leading, spacing: 4) {
            Text("AUDIT TRAIL")
                .font(Theme.Font.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.Color.accent)
            Text("Tamper-Evident Log")
                .font(Theme.Font.display(26, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
            HStack(spacing: 6) {
                Text("\(count) events")
                Text("·")
                Text("chain " + (broken ? "BROKEN" : "OK"))
                    .foregroundStyle(broken ? Theme.Color.danger : Theme.Color.success)
            }
            .font(Theme.Font.mono(12))
            .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chainCard: some View {
        let total = state.audit.events.count
        let brokenIndex = state.audit.verifyChain()
        let last = state.audit.events.last
        let lastHash = last?.hash ?? String(repeating: "0", count: 64)
        let genesisOk = (state.audit.events.first?.prevHash ?? String(repeating: "0", count: 64)) == String(repeating: "0", count: 64)
        return GlassCard(tint: brokenIndex == nil ? Theme.Color.success : Theme.Color.danger) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Chain Integrity", subtitle: nil)
                    Spacer()
                    if let idx = brokenIndex {
                        StatusPill(text: "BROKEN @ \(idx)", tone: .danger, icon: "exclamationmark.triangle.fill")
                    } else {
                        StatusPill(text: "VERIFIED", tone: .success, icon: "checkmark.seal.fill", pulses: true)
                    }
                }
                KVRow(key: "Total events", value: "\(total)")
                KVRow(key: "Genesis link", value: genesisOk ? "OK" : "MISSING",
                      valueColor: genesisOk ? Theme.Color.success : Theme.Color.danger)
                KVRow(key: "Verification", value: brokenIndex == nil ? "all links match" : "first break at idx \(brokenIndex!)",
                      valueColor: brokenIndex == nil ? Theme.Color.success : Theme.Color.danger)
                HStack(spacing: 10) {
                    HashGlyph(hash: lastHash, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LAST HASH")
                            .font(Theme.Font.mono(9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(Fmt.shortHash(lastHash))
                            .font(Theme.Font.mono(12, weight: .medium))
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        let allKinds = AuditEvent.Kind.allCases
        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Filter", subtitle: nil)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    chip(label: "All", icon: "tray.full", tone: .accent, choice: .all)
                    ForEach(allKinds, id: \.self) { k in
                        chip(label: shortLabel(k), icon: k.icon, tone: k.tone, choice: .kind(k))
                    }
                }
            }
        }
    }

    private func chip(label: String, icon: String, tone: PillTone, choice: FilterChoice) -> some View {
        let selected = selectedFilter == choice
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedFilter = choice
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(Theme.Font.mono(10, weight: .semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
            }
            .foregroundStyle(selected ? Color.black : tone.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? tone.fg : tone.bg)
            )
            .overlay(
                Capsule().strokeBorder(tone.border, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func shortLabel(_ k: AuditEvent.Kind) -> String {
        switch k {
        case .proposalGenerated:   return "Proposal"
        case .policyEvaluated:     return "Policy"
        case .approvalRequested:   return "Req"
        case .approvalGranted:     return "Granted"
        case .approvalRejected:    return "Rejected"
        case .approvalExpired:     return "Expired"
        case .orderSubmitted:      return "Submit"
        case .orderFilled:         return "Filled"
        case .executionBlocked:    return "Blocked"
        case .killSwitchActivated: return "Kill On"
        case .killSwitchCleared:   return "Kill Off"
        case .modeChanged:         return "Mode"
        case .reconciled:          return "Recon"
        }
    }

    // MARK: - Events list

    private var filteredEvents: [AuditEvent] {
        let base = state.audit.events.reversed()
        switch selectedFilter {
        case .all:           return Array(base)
        case .kind(let k):   return base.filter { $0.kind == k }
        }
    }

    private var eventsList: some View {
        let events = filteredEvents
        return Group {
            if events.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(events) { ev in
                        eventRow(ev)
                    }
                }
            }
        }
    }

    private func eventRow(_ ev: AuditEvent) -> some View {
        let isOpen = expanded.contains(ev.id)
        let tone = ev.kind.tone
        return GlassCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                // Left rail
                VStack(spacing: 0) {
                    Circle()
                        .fill(tone.fg)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().strokeBorder(tone.fg.opacity(0.5), lineWidth: 4)
                                .blur(radius: 1)
                        )
                    Rectangle()
                        .fill(LinearGradient(colors: [tone.fg.opacity(0.6), tone.fg.opacity(0.0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 12)

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        StatusPill(text: pillText(ev.kind), tone: tone, icon: ev.kind.icon)
                        Spacer()
                        Text(formatted(ev.timestamp))
                            .font(Theme.Font.mono(10))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    Text(ev.summary)
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Color.textTertiary)
                        Text(ev.actor)
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Color.textSecondary)
                        Spacer()
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }

                    if isOpen {
                        VStack(alignment: .leading, spacing: 8) {
                            Divider().overlay(Theme.Color.surfaceStroke)
                            if ev.payload.isEmpty {
                                Text("No payload.")
                                    .font(Theme.Font.body(12))
                                    .foregroundStyle(Theme.Color.textTertiary)
                            } else {
                                ForEach(ev.payload.keys.sorted(), id: \.self) { key in
                                    KVRow(key: key, value: ev.payload[key] ?? "—")
                                }
                            }
                            Divider().overlay(Theme.Color.surfaceStroke)
                            hashRow(label: "PREV", hash: ev.prevHash)
                            hashRow(label: "HASH", hash: ev.hash)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                if isOpen { expanded.remove(ev.id) } else { expanded.insert(ev.id) }
            }
        }
    }

    private func hashRow(label: String, hash: String) -> some View {
        HStack(spacing: 10) {
            HashGlyph(hash: hash, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Theme.Font.mono(9, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(Fmt.shortHash(hash))
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
    }

    private func pillText(_ k: AuditEvent.Kind) -> String {
        k.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("No events match filter.")
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            NeonButton(title: "Verify Chain", icon: "checkmark.shield", tone: .accent, fill: true) {
                let result = state.audit.verifyChain()
                let ok = result == nil
                showToast(ok ? "Chain verified · all links intact" : "Chain BROKEN at index \(result!)",
                          tone: ok ? .success : .danger)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color.clear, Theme.Color.bgDeep.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func showToast(_ text: String, tone: PillTone) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            toastText = text
            toastTone = tone
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                toastText = nil
            }
        }
    }

    private func toast(text: String, tone: PillTone) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tone == .success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tone.fg)
            Text(text)
                .font(Theme.Font.body(13, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(tone.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }
}

// MARK: - Tiny flow layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
