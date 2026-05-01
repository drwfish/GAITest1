import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: Tab = .dashboard

    enum Tab: Hashable {
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

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $selection) {
                DashboardView()
                    .tabItem { Label(Tab.dashboard.label, systemImage: Tab.dashboard.icon) }
                    .tag(Tab.dashboard)

                ProposalsView()
                    .tabItem { Label(Tab.proposals.label, systemImage: Tab.proposals.icon) }
                    .tag(Tab.proposals)

                ApprovalQueueView()
                    .tabItem { Label(Tab.approvals.label, systemImage: Tab.approvals.icon) }
                    .badge(state.openCases.count > 0 ? state.openCases.count : 0)
                    .tag(Tab.approvals)

                AuditTrailView()
                    .tabItem { Label(Tab.audit.label, systemImage: Tab.audit.icon) }
                    .tag(Tab.audit)

                GovernanceView()
                    .tabItem { Label(Tab.governance.label, systemImage: Tab.governance.icon) }
                    .tag(Tab.governance)
            }
            .tint(Theme.Color.accent)
        }
    }
}
