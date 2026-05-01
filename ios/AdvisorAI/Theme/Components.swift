import SwiftUI

// MARK: - Glass card

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Theme.Radius.lg
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
            )
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (tint ?? Theme.Color.accent).opacity(0.35),
                                Theme.Color.surfaceStroke
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 14)
    }
}

// MARK: - Status pill

enum PillTone {
    case success, warn, danger, info, neutral, accent

    var fg: Color {
        switch self {
        case .success: return Theme.Color.success
        case .warn:    return Theme.Color.warn
        case .danger:  return Theme.Color.danger
        case .info:    return Theme.Color.info
        case .neutral: return Theme.Color.textSecondary
        case .accent:  return Theme.Color.accent
        }
    }
    var bg: Color { fg.opacity(0.14) }
    var border: Color { fg.opacity(0.45) }
}

struct StatusPill: View {
    let text: String
    var tone: PillTone = .neutral
    var icon: String? = nil
    var pulses: Bool = false

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            if pulses {
                Circle()
                    .fill(tone.fg)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(tone.fg, lineWidth: 1.2)
                            .scaleEffect(pulse ? 2.2 : 1.0)
                            .opacity(pulse ? 0 : 0.8)
                    )
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                            pulse = true
                        }
                    }
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(Theme.Font.mono(11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(tone.fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(tone.bg)
        )
        .overlay(
            Capsule().strokeBorder(tone.border, lineWidth: 0.8)
        )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(Theme.Font.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.Color.accent)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.display(20, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Key/value rows

struct KVRow: View {
    let key: String
    let value: String
    var valueMono: Bool = true
    var valueColor: Color = Theme.Color.textPrimary

    var body: some View {
        HStack {
            Text(key)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text(value)
                .font(valueMono ? Theme.Font.mono(13, weight: .medium) : Theme.Font.body(13, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Neon button

struct NeonButton: View {
    let title: String
    var icon: String? = nil
    var tone: PillTone = .accent
    var fill: Bool = true
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(Theme.Font.body(14, weight: .semibold))
            .foregroundStyle(fill ? Color.black : tone.fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Group {
                    if fill {
                        Capsule().fill(tone.fg)
                    } else {
                        Capsule().fill(tone.fg.opacity(0.12))
                    }
                }
            )
            .overlay(
                Capsule().strokeBorder(tone.fg.opacity(fill ? 0 : 0.5), lineWidth: 1)
            )
            .shadow(color: fill ? tone.fg.opacity(0.45) : .clear, radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1.0)
        .disabled(disabled)
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var tone: Color = Theme.Color.accent
    var fill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            guard values.count > 1 else { return AnyView(EmptyView()) }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(0.0001, maxV - minV)
            let pts: [CGPoint] = values.enumerated().map { idx, v in
                let x = CGFloat(idx) / CGFloat(values.count - 1) * w
                let y = h - CGFloat((v - minV) / range) * h
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            line.move(to: pts[0])
            for p in pts.dropFirst() { line.addLine(to: p) }

            var area = line
            area.addLine(to: CGPoint(x: w, y: h))
            area.addLine(to: CGPoint(x: 0, y: h))
            area.closeSubpath()

            return AnyView(
                ZStack {
                    if fill {
                        area.fill(
                            LinearGradient(
                                colors: [tone.opacity(0.35), tone.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    line.stroke(tone, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            )
        }
    }
}

// MARK: - Hash glyph

/// Renders a stable visual identity for a hex hash (last N chars become 4x4 dots).
struct HashGlyph: View {
    let hash: String
    var size: CGFloat = 22

    var body: some View {
        let chars = Array(hash.suffix(16))
        let cell = size / 4
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.Color.surfaceHi)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.Color.accent.opacity(0.4), lineWidth: 0.6)
                )

            VStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<4, id: \.self) { col in
                            let i = row * 4 + col
                            let c = i < chars.count ? chars[i] : "0"
                            let val = Int(String(c), radix: 16) ?? 0
                            let on = val >= 8
                            Rectangle()
                                .fill(on ? Theme.Color.accent : Color.clear)
                                .frame(width: cell - 1.5, height: cell - 1.5)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Animated meter (gauge)

struct Meter: View {
    let label: String
    let value: Double         // 0...1
    let limit: Double         // 0...1 limit threshold
    var tone: Color = Theme.Color.accent
    var format: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text(format(value))
                    .font(Theme.Font.mono(12, weight: .semibold))
                    .foregroundStyle(value > limit ? Theme.Color.danger : Theme.Color.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 6)
                    Capsule()
                        .fill(value > limit ? Theme.Gradient.dangerHorizon
                              : LinearGradient(colors: [tone, tone.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(1, value)) * geo.size.width, height: 6)
                    // limit marker
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1.4, height: 12)
                        .offset(x: limit * geo.size.width - 0.7, y: 0)
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Money / number formatting

enum Fmt {
    static func usd(_ v: Double, decimals: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = decimals
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
    static func qty(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func pct(_ v: Double, decimals: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = decimals
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func shortHash(_ h: String) -> String {
        guard h.count > 12 else { return h }
        return String(h.prefix(6)) + "…" + String(h.suffix(4))
    }
}
