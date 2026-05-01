import Foundation
import Combine

@MainActor
final class MarketDataService: ObservableObject {
    /// Symbol → snapshot.
    @Published private(set) var snapshots: [String: MarketSnapshot] = [:]
    @Published private(set) var feedHealthy: Bool = true
    @Published private(set) var lastTick: Date = Date()

    private var timer: Timer?

    func seed(symbols: [String]) {
        for s in symbols {
            snapshots[s] = Self.initialSnapshot(for: s)
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func degradeFeed() {
        feedHealthy = false
        for (k, v) in snapshots {
            snapshots[k] = MarketSnapshot(
                symbol: v.symbol,
                bid: v.bid, ask: v.ask, last: v.last,
                dayChangePct: v.dayChangePct,
                avgDailyVolume: v.avgDailyVolume,
                venueLatencyMs: v.venueLatencyMs,
                asOf: v.asOf, fresh: false,
                summary: "Stale: feed degraded.",
                intraday: v.intraday
            )
        }
    }

    func restoreFeed() {
        feedHealthy = true
        tick()
    }

    private func tick() {
        guard feedHealthy else { return }
        lastTick = Date()
        for (k, v) in snapshots {
            let drift = Double.random(in: -0.0035...0.0035)
            let last = max(0.5, v.last * (1 + drift))
            let bid = last * (1 - 0.0005)
            let ask = last * (1 + 0.0005)
            var intra = v.intraday
            intra.append(last)
            if intra.count > 64 { intra.removeFirst(intra.count - 64) }
            snapshots[k] = MarketSnapshot(
                symbol: v.symbol,
                bid: bid, ask: ask, last: last,
                dayChangePct: v.dayChangePct + drift,
                avgDailyVolume: v.avgDailyVolume,
                venueLatencyMs: Double.random(in: 4...18),
                asOf: Date(),
                fresh: true,
                summary: Self.summary(for: k, change: v.dayChangePct + drift),
                intraday: intra
            )
        }
    }

    static func initialSnapshot(for symbol: String) -> MarketSnapshot {
        let base = seedPrice(for: symbol)
        let change = Double.random(in: -0.018...0.022)
        var trail: [Double] = []
        var v = base * (1 - change)
        for _ in 0..<48 {
            v *= 1 + Double.random(in: -0.0025...0.0025)
            trail.append(v)
        }
        trail.append(base)
        return MarketSnapshot(
            symbol: symbol,
            bid: base * 0.9995,
            ask: base * 1.0005,
            last: base,
            dayChangePct: change,
            avgDailyVolume: avgVolume(for: symbol),
            venueLatencyMs: Double.random(in: 5...14),
            asOf: Date(),
            fresh: true,
            summary: summary(for: symbol, change: change),
            intraday: trail
        )
    }

    private static func summary(for symbol: String, change: Double) -> String {
        let dir = change >= 0 ? "up" : "down"
        return "\(symbol) \(dir) \(String(format: "%.2f", abs(change) * 100))% intraday with normal liquidity."
    }

    private static func seedPrice(for symbol: String) -> Double {
        switch symbol {
        case "AAPL": return 224.50
        case "MSFT": return 478.20
        case "NVDA": return 142.10
        case "AMZN": return 218.80
        case "GOOGL": return 198.40
        case "META": return 712.30
        case "TSLA": return 312.60
        case "AVGO": return 184.90
        case "JPM":  return 268.40
        case "BRK.B": return 471.10
        case "XOM":  return 116.40
        case "VTI":  return 296.80
        case "IEF":  return 92.30
        case "GLD":  return 312.40
        default:     return 100.0
        }
    }

    private static func avgVolume(for symbol: String) -> Double {
        switch symbol {
        case "AAPL": return 58_000_000
        case "NVDA": return 240_000_000
        case "TSLA": return 95_000_000
        case "MSFT": return 24_000_000
        default:     return 12_000_000
        }
    }
}
