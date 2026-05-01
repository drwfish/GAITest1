# AdvisorAI — iOS POC

A SwiftUI proof of concept that turns the architecture from
[`Secure Open-Source Architecture for an Advisor-Assisted AI Trading System`](../README.md)
into a tangible, navigable iOS app. It models the **split-plane** principle the document argues
for: **AI may propose and explain, but deterministic services must decide and execute.**

> Status: POC. All data is synthetic; no broker is wired in. Nothing here is investment advice
> and nothing routes real orders.

---

## Why this exists

The source document recommends a compositional stack: a deterministic engine (Lean / Nautilus),
a research layer (Qlib / PyPortfolioOpt), a policy engine (OPA), a durable workflow (Temporal),
and end-to-end telemetry — with an LLM copilot relegated to the advisory plane only. This POC
makes that pattern concrete on a phone or tablet so an advisor can:

1. See AI-generated trade proposals with full rationale and signals.
2. Watch a typed proposal flow through the deterministic gates: ingest → validate → signal →
   optimize → risk → policy → approval → OMS → broker → reconcile.
3. Approve or reject in a HITL queue, with **dual control** when notional crosses a threshold.
4. Inspect a tamper-evident, hash-chained audit trail of every event in the system.
5. Operate trading mode (Research / Paper / Canary / Live), the kill switch, and feed health.

## What's in the box

| Plane | Component | Role |
| --- | --- | --- |
| Advisory | `AIAdvisorService` | Generates typed `Proposal`s with rationale, signals, risks, citations |
| Deterministic | `MarketDataService` | Live-ticking mock quotes with freshness flag |
| Deterministic | `RiskEngine` | Marketability, price band, cash, concentration, drawdown |
| Deterministic | `PolicyEngine` | OPA-style deny-by-default rules (mode, capital cap, restricted list, asset class) |
| Deterministic | `ApprovalWorkflow` | Durable cases, deadlines, dual-control, signed approval token |
| Deterministic | `OMS` | Fail-closed submission with idempotency + token signature verify |
| Deterministic | `AuditLog` | SHA-256 hash-chained, append-only event log |
| Deterministic | `KillSwitch` | Global halt observable from every service |

## App map

```
Dashboard      Mission Control overview, holdings, risk gauges, system health, activity
Proposals      Advisory plane — AI proposals + the animated split-plane Pipeline
Approvals      HITL queue: pending, approved, rejected, blocked, expired
Audit          Hash-chained event log with chain verification
Governance     Mode switcher, kill switch, feed health, policy rules, architecture legend
```

## Architectural rule (enforced in code)

```
proposal (advisory plane) → submitForApproval(...)
    └─ RiskEngine.evaluate     ──┐
    └─ PolicyEngine.evaluate     ├─ deny-by-default
                                 │
    └─ Workflow opens case  ←────┘   (state: pending|blocked)
       └─ HITL approver(s) decide
       └─ Workflow issues signed token bound to intent_hash
       └─ OMS.submit(intent, token, market, risk)
          ├─ verifies hash binding, signature, expiry
          ├─ idempotency + freshness checks
          └─ submits or fails closed
       └─ AuditLog.append(...)  every transition, hash-chained
```

The AI plane never holds a write path to the OMS. Submitting a proposal *opens* a case; only
a valid approval token from the workflow lets the OMS submit, and the OMS verifies the token
binds to the exact intent hash before sending.

## Build & run

You need macOS, Xcode 15.4+, iOS 17 SDK, and either [XcodeGen](https://github.com/yonaskolb/XcodeGen)
or a willingness to drag the source folder into a fresh Xcode project.

### Option A — XcodeGen (recommended)

```bash
brew install xcodegen
cd ios
xcodegen generate
open AdvisorAI.xcodeproj
```

Then ⌘R to run on the iPhone or iPad simulator.

### Option B — manual Xcode setup

1. Xcode → File → New → Project → **App** (iOS) → "AdvisorAI", Interface: SwiftUI, Language: Swift.
2. Delete the default `ContentView.swift` and `AdvisorAIApp.swift`.
3. Drag the entire `ios/AdvisorAI/` folder into the project navigator (Copy items if needed: NO,
   Create folder references: YES, add to target: AdvisorAI).
4. Project settings → Info → set **User Interface Style** to **Dark**, deployment target 17.0.
5. Build & run.

## What to demo

A 60-second tour:

1. **Dashboard** — Watch the mini-market sparklines tick and the activity feed populate.
2. **Proposals** — Tap *Generate Proposal*. A new card animates in. Tap *Inspect* to open the
   Pipeline visualization; the beam flows through every stage.
3. **Submit for Approval** — back in Proposals or detail view, submit the proposal. The case
   appears in *Approvals* with a live countdown.
4. **Approve** — open the case, review the policy reasons (every rule listed pass/fail), tap
   *Approve*. If notional > $250k, you'll be asked for a second approver (compliance officer).
   Once both sign, an approval token is issued, the OMS fills the order, and a fresh
   reconciliation event lands in the Audit tab.
5. **Audit** — every transition appears with hash-chain linkage. Tap *Verify Chain*.
6. **Governance** — flip the kill switch. Try to approve another pending case. The OMS fails
   closed and the audit log records `EXECUTION_BLOCKED`. Restore feed health, clear the kill
   switch, switch modes and watch the capital cap policy kick in.

## File map

```
ios/
├── project.yml                        XcodeGen spec
└── AdvisorAI/
    ├── App/                           Entry, AppState orchestrator, RootView tabs
    ├── Theme/                         Colors, gradients, glass cards, pills, sparkline, hash glyph
    ├── Models/                        TradeIntent, Snapshots, Policy, Approval, Audit, Pipeline
    ├── Services/                      AIAdvisor, MarketData, Risk, Policy, Workflow, OMS, Audit, KillSwitch, MockData
    ├── Features/
    │   ├── Dashboard/
    │   ├── Proposals/                 ProposalsView, ProposalDetailView, PipelineView (the animated hero)
    │   ├── Approvals/                 Queue + Detail with HITL + dual control
    │   ├── Audit/                     Hash-chain timeline
    │   └── Governance/                Mode, kill switch, feed, policy registry
    └── Resources/
        └── Assets.xcassets/
```

## What this POC is NOT

- It is not a trading system. There is no broker adapter, no real market data, no real money.
- It does not implement OPA, Temporal, or an OMS — it models their behaviors so the architecture
  is *demonstrable* on device. Replace the mock services with real ones to productionize.
- Nothing here represents legal/compliance advice; supervisory and recordkeeping requirements
  vary by jurisdiction and entity type (see the parent document for citations).

## License

POC code; treat as Apache-2.0 unless your wider repo policy says otherwise.
