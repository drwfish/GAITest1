import Foundation

enum MockData {

    static let symbols = [
        "AAPL", "MSFT", "NVDA", "AMZN", "GOOGL",
        "META", "TSLA", "AVGO", "JPM", "BRK.B",
        "XOM", "VTI", "IEF", "GLD"
    ]

    static func sectors(for symbol: String) -> String {
        switch symbol {
        case "AAPL", "MSFT", "NVDA", "AVGO", "GOOGL", "META": return "Technology"
        case "AMZN", "TSLA":                                   return "Consumer"
        case "JPM", "BRK.B":                                   return "Financials"
        case "XOM":                                            return "Energy"
        case "VTI":                                            return "Broad Equity"
        case "IEF":                                            return "Treasuries"
        case "GLD":                                            return "Commodities"
        default:                                               return "Other"
        }
    }

    static func accounts() -> [Account] {
        [
            Account(
                id: "ACCT-A1027",
                name: "Halverson Family Trust",
                owner: "M. Halverson",
                aum: 2_840_000,
                cash: 142_500,
                mandate: Mandate(
                    strategy: "core-balanced-2026",
                    maxPositionPct: 0.08,
                    maxSectorPct: 0.32,
                    maxDrawdownPct: 0.12,
                    allowedAssetClasses: ["us_equity", "etf"]
                ),
                restrictions: ["TSLA"]
            ),
            Account(
                id: "ACCT-B2204",
                name: "Okafor Retirement IRA",
                owner: "C. Okafor",
                aum: 1_120_000,
                cash: 86_300,
                mandate: Mandate(
                    strategy: "growth-tilt-2026",
                    maxPositionPct: 0.10,
                    maxSectorPct: 0.40,
                    maxDrawdownPct: 0.15,
                    allowedAssetClasses: ["us_equity", "etf"]
                ),
                restrictions: []
            ),
            Account(
                id: "ACCT-C5891",
                name: "Park Endowment Sleeve",
                owner: "Park Foundation",
                aum: 8_300_000,
                cash: 410_000,
                mandate: Mandate(
                    strategy: "endowment-conservative",
                    maxPositionPct: 0.05,
                    maxSectorPct: 0.25,
                    maxDrawdownPct: 0.08,
                    allowedAssetClasses: ["us_equity", "etf"]
                ),
                restrictions: ["XOM"]
            )
        ]
    }

    static func positions(for accounts: [Account]) -> [Position] {
        var result: [Position] = []
        let recipes: [(String, [(String, Double)])] = [
            ("ACCT-A1027", [
                ("AAPL", 580), ("MSFT", 240), ("NVDA", 1_400), ("VTI", 2_100),
                ("JPM", 320), ("GLD", 240), ("IEF", 1_800)
            ]),
            ("ACCT-B2204", [
                ("NVDA", 900), ("AVGO", 280), ("GOOGL", 410), ("META", 120),
                ("AMZN", 220), ("VTI", 1_100)
            ]),
            ("ACCT-C5891", [
                ("VTI", 8_400), ("IEF", 14_000), ("GLD", 1_200), ("BRK.B", 1_900),
                ("MSFT", 540), ("AAPL", 720), ("JPM", 480)
            ])
        ]
        for (acct, items) in recipes {
            for (sym, qty) in items {
                let mark = MarketDataService.initialSnapshot(for: sym).last
                let avgCost = mark * Double.random(in: 0.82...1.04)
                result.append(Position(
                    account: acct,
                    symbol: sym,
                    sector: sectors(for: sym),
                    qty: qty,
                    avgCost: avgCost,
                    mark: mark
                ))
            }
        }
        return result
    }

    /// Default approvers (used as the signed-in advisor and a backup compliance officer).
    static let advisor = Approver(
        id: "u-advisor",
        name: "You (Advisor)",
        role: "Lead Advisor",
        decidedAt: Date(),
        decision: .approved
    )
    static let compliance = Approver(
        id: "u-compliance",
        name: "K. Reyes",
        role: "Compliance Officer",
        decidedAt: Date(),
        decision: .approved
    )

    static let allApprovers: [Approver] = [advisor, compliance]
}
