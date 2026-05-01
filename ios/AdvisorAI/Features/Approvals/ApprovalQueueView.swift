import SwiftUI

// MARK: - Filter

private enum ApprovalFilter: String, CaseIterable, Identifiable {
    case all      = "All"
    case pending  = "Pending"
    case approved = "Approved"
    case rejected = "Rejected"
    case blocked  = "Blocked"
    case expired  = "Expired"

    var id: String { rawValue }

    var tone: PillTone {
        switch self {
        case .all:      return .accent
        case .pending:  return .accent
        case .approved: return .success
        case .rejected: return .danger
        case .blocked:  return .danger
        case .expired:  return .warn
        }
    }

    var emptyIcon: String {
        switch self {
        case .all:      return "tray"
        case .pending:  return "hourglass"
        case .approved: return "checkmark.seal"
        case .rejected: return "xmark.seal"
        case .blocked:  return "hand.raised"
        case .expired:  return "clock.badge.xmark"
        }
    }

    var emptyCopy: String {
        switch self {
        case .all:      return "No approval cases yet. Generate a proposal to populate the queue."
        case .pending:  return "Nothing waiting on a human. The queue is clear."
        case .approved: return "No approved cases in this window."
        case .rejected: return "No rejections recorded."
        case .blocked:  return "No policy-blocked cases."
        case .expired:  return "No deadlines have lapsed."
        }
    }
}

// MARK: - Status pill mapping

private extension ApprovalState {
    var pill: (text: String, tone: PillTone, pulses: Bool) {
        switch self {
        case .pending:   return ("Pending",   .accent,  true)
        case .approved:  return ("Approved",  .success, false)
        case .rejected:  return ("Rejected",  .danger,  false)
        case .expired:   return ("Expired",   .warn,    false)
        case .blocked:   return ("Blocked",   .danger,  false)
        case .executing: return ("Executing", .info,    true)
        case .filled:    return ("Filled",    .success, false)
        case .canceled:  return ("Canceled",  .neutral, false)
        }
    }
}

// MARK: - View

struct ApprovalQueueView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var filter: ApprovalFilter = .all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    filterRow
                    contentBody
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .background(Color.clear)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !state.openCases.isEmpty {
                        Menu {
                            Text("Tip: tap a case to review.")
                            Text("HITL is per-case by design.")
                            Text("There is no one-tap mass approval.")
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(Theme.Color.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let pending = counts.pending
        let approvedToday = counts.approvedToday
        let rejectedToday = counts.rejectedToday
        return VStack(alignment: .leading, spacing: 6) {
            Text("APPROVALS")
                .font(Theme.Font.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.Color.accent)
            Text("Approvals")
                .font(Theme.Font.display(30, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
            HStack(spacing: 6) {
                Text("\(pending) pending")
                    .foregroundStyle(Theme.Color.accent)
                Text("·").foregroundStyle(Theme.Color.textTertiary)
                Text("\(approvedToday) approved today")
                    .foregroundStyle(Theme.Color.success)
                Text("·").foregroundStyle(Theme.Color.textTertiary)
                Text("\(rejectedToday) rejected today")
                    .foregroundStyle(Theme.Color.danger)
            }
            .font(Theme.Font.mono(12, weight: .medium))
            Text("AI proposes · policy decides · humans approve.")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var counts: (pending: Int, approvedToday: Int, rejectedToday: Int) {
        let cases = state.workflow.cases
        let cal = Calendar.current
        let pending = cases.filter { $0.state == .pending }.count
        let approvedToday = cases.filter {
            ($0.state == .approved || $0.state == .executing || $0.state == .filled) &&
            cal.isDateInToday($0.createdAt)
        }.count
        let rejectedToday = cases.filter {
            ($0.state == .rejected || $0.state == .blocked || $0.state == .expired) &&
            cal.isDateInToday($0.createdAt)
        }.count
        return (pending, approvedToday, rejectedToday)
    }

    // MARK: Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ApprovalFilter.allCases) { f in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            filter = f
                        }
                    } label: {
                        StatusPill(
                            text: "\(f.rawValue)  \(count(for: f))",
                            tone: f == filter ? f.tone : .neutral
                        )
                        .opacity(f == filter ? 1.0 : 0.78)
                        .scaleEffect(f == filter ? 1.04 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private func count(for f: ApprovalFilter) -> Int {
        switch f {
        case .all:      return state.workflow.cases.count
        case .pending:  return state.workflow.cases.filter { $0.state == .pending }.count
        case .approved: return state.workflow.cases.filter {
            $0.state == .approved || $0.state == .executing || $0.state == .filled
        }.count
        case .rejected: return state.workflow.cases.filter { $0.state == .rejected }.count
        case .blocked:  return state.workflow.cases.filter { $0.state == .blocked }.count
        case .expired:  return state.workflow.cases.filter { $0.state == .expired }.count
        }
    }

    private var filtered: [ApprovalCase] {
        let all = state.workflow.cases.sorted { $0.createdAt > $1.createdAt }
        switch filter {
        case .all:      return all
        case .pending:  return all.filter { $0.state == .pending }
        case .approved: return all.filter {
            $0.state == .approved || $0.state == .executing || $0.state == .filled
        }
        case .rejected: return all.filter { $0.state == .rejected }
        case .blocked:  return all.filter { $0.state == .blocked }
        case .expired:  return all.filter { $0.state == .expired }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var contentBody: some View {
        let cases = filtered
        if cases.isEmpty {
            emptyState
        } else if hSize == .regular {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 18)], spacing: 18) {
                ForEach(cases) { kase in
                    NavigationLink(value: kase.id) {
                        ApprovalRow(kase: kase)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let live = state.workflow.cases.first(where: { $0.id == id }) {
                    ApprovalDetailView(approvalCase: live)
                }
            }
        } else {
            VStack(spacing: 14) {
                ForEach(cases) { kase in
                    NavigationLink(value: kase.id) {
                        ApprovalRow(kase: kase)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let live = state.workflow.cases.first(where: { $0.id == id }) {
                    ApprovalDetailView(approvalCase: live)
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: filter.emptyIcon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("Queue is quiet")
                    .font(Theme.Font.display(18, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(filter.emptyCopy)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }
}

// MARK: - Approval row

private struct ApprovalRow: View {
    let kase: ApprovalCase

    private var sideTone: PillTone {
        kase.proposal.intent.side == .buy ? .success : .danger
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                topLine
                subLine
                if kase.state == .pending {
                    countdown
                } else {
                    staticState
                }
                gates
            }
        }
    }

    // Header line: side, symbol, qty/limit, notional, status
    private var topLine: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusPill(
                text: kase.proposal.intent.side.rawValue,
                tone: sideTone
            )
            Text(kase.proposal.intent.symbol)
                .font(Theme.Font.mono(20, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Fmt.qty(kase.proposal.intent.qty)) @ \(Fmt.usd(kase.proposal.intent.limitPrice ?? kase.proposal.market.last, decimals: 2))")
                    .font(Theme.Font.mono(11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(Fmt.usd(kase.proposal.notional))
                    .font(Theme.Font.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Spacer()
            let s = kase.state.pill
            StatusPill(text: s.text, tone: s.tone, pulses: s.pulses)
        }
    }

    private var subLine: some View {
        HStack(spacing: 10) {
            Label(kase.proposal.intent.accountId, systemImage: "person.crop.square")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.textSecondary)
            Text("·").foregroundStyle(Theme.Color.textTertiary)
            Label(kase.proposal.intent.strategyId, systemImage: "waveform.path.ecg")
                .font(Theme.Font.body(11))
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text(relativeTime(kase.createdAt))
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    @ViewBuilder
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let remaining = max(0, kase.deadline.timeIntervalSinceNow)
            let total = max(1, kase.deadline.timeIntervalSince(kase.createdAt))
            let frac = max(0.0, min(1.0, remaining / total))
            let tone: Color = {
                if remaining < 30 { return Theme.Color.danger }
                if remaining < 120 { return Theme.Color.warn }
                return Theme.Color.accent
            }()

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Approval window")
                        .font(Theme.Font.body(11))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                    Text(formatRemaining(remaining))
                        .font(Theme.Font.mono(11, weight: .semibold))
                        .foregroundStyle(tone)
                }
                .foregroundStyle(Theme.Color.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [tone, tone.opacity(0.55)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * frac, height: 4)
                            .animation(.linear(duration: 0.5), value: frac)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    @ViewBuilder
    private var staticState: some View {
        HStack(spacing: 8) {
            Image(systemName: stateIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stateColor)
            Text(stateLabel)
                .font(Theme.Font.body(11))
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
    }

    private var stateIcon: String {
        switch kase.state {
        case .approved:  return "checkmark.seal.fill"
        case .rejected:  return "xmark.seal.fill"
        case .expired:   return "clock.badge.xmark"
        case .blocked:   return "hand.raised.fill"
        case .executing: return "paperplane.fill"
        case .filled:    return "checkmark.circle.fill"
        case .canceled:  return "minus.circle"
        case .pending:   return "hourglass"
        }
    }
    private var stateColor: Color {
        switch kase.state.pill.tone {
        case .success: return Theme.Color.success
        case .warn:    return Theme.Color.warn
        case .danger:  return Theme.Color.danger
        case .info:    return Theme.Color.info
        case .accent:  return Theme.Color.accent
        case .neutral: return Theme.Color.textSecondary
        }
    }
    private var stateLabel: String {
        switch kase.state {
        case .approved:  return "Approved · token issued"
        case .rejected:  return "Rejected by approver"
        case .expired:   return "Approval window expired"
        case .blocked:   return kase.blockReason ?? "Execution blocked"
        case .executing: return "Routing to broker"
        case .filled:    return "Filled · reconciled"
        case .canceled:  return "Canceled"
        case .pending:   return "Pending"
        }
    }

    // Compact gate pipeline
    private var gates: some View {
        HStack(spacing: 6) {
            ForEach(kase.policy.reasons) { r in
                gatePill(r)
            }
            Spacer(minLength: 0)
        }
    }

    private func gatePill(_ r: PolicyReason) -> some View {
        HStack(spacing: 3) {
            Image(systemName: r.passed ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .heavy))
            Text(shortRule(r.rule))
                .font(Theme.Font.mono(9, weight: .semibold))
        }
        .foregroundStyle(r.passed ? Theme.Color.success : Theme.Color.danger)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((r.passed ? Theme.Color.success : Theme.Color.danger).opacity(0.12))
        )
        .overlay(
            Capsule().strokeBorder(
                (r.passed ? Theme.Color.success : Theme.Color.danger).opacity(0.4),
                lineWidth: 0.6)
        )
    }

    private func shortRule(_ rule: String) -> String {
        // last segment, uppercased to keep compact
        let last = rule.split(separator: ".").last.map(String.init) ?? rule
        return last.replacingOccurrences(of: "_", with: " ")
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatRemaining(_ s: TimeInterval) -> String {
        if s <= 0 { return "00:00" }
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}
