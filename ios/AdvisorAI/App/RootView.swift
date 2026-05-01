import SwiftUI

enum AppTab: String, Hashable {
    case dashboard, proposals, approvals, audit, governance

    var label: String {
        switch self {
        case .dashboard:  return "Dashboard"
        case .proposals:  return "Proposals"
        case .approvals:  return "Approvals"
        case .audit:      return "Audit"
        case .governance: return "Governance"
        }
    }
    var icon: String {
        switch self {
        case .dashboard:  return "chart.line.uptrend.xyaxis"
        case .proposals:  return "sparkles.rectangle.stack"
        case .approvals:  return "person.badge.shield.checkmark"
        case .audit:      return "doc.text.magnifyingglass"
        case .governance: return "lock.shield"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: AppTab = .dashboard

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $selection) {
                DashboardView()
                    .tabItem { Label(AppTab.dashboard.label, systemImage: AppTab.dashboard.icon) }
                    .tag(AppTab.dashboard)

                ProposalsView()
                    .tabItem { Label(AppTab.proposals.label, systemImage: AppTab.proposals.icon) }
                    .tag(AppTab.proposals)

                ApprovalQueueView()
                    .tabItem { Label(AppTab.approvals.label, systemImage: AppTab.approvals.icon) }
                    .badge(state.openCases.count > 0 ? state.openCases.count : 0)
                    .tag(AppTab.approvals)

                AuditTrailView()
                    .tabItem { Label(AppTab.audit.label, systemImage: AppTab.audit.icon) }
                    .tag(AppTab.audit)

                GovernanceView()
                    .tabItem { Label(AppTab.governance.label, systemImage: AppTab.governance.icon) }
                    .tag(AppTab.governance)
            }
            .tint(Theme.Color.accent)
            .onChange(of: state.requestedTab) { _, new in
                if let new {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        selection = new
                    }
                    state.requestedTab = nil
                }
            }
        }
    }
}
