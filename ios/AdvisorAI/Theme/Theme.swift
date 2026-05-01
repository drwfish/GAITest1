import SwiftUI

enum Theme {
    enum Color {
        static let bgDeep = SwiftUI.Color(red: 0.027, green: 0.035, blue: 0.078)      // #070914
        static let bgMid  = SwiftUI.Color(red: 0.039, green: 0.055, blue: 0.110)      // #0A0E1C
        static let bgLift = SwiftUI.Color(red: 0.066, green: 0.090, blue: 0.165)      // #11172A

        static let surface       = SwiftUI.Color.white.opacity(0.04)
        static let surfaceStroke = SwiftUI.Color.white.opacity(0.08)
        static let surfaceHi     = SwiftUI.Color.white.opacity(0.07)

        static let textPrimary   = SwiftUI.Color.white.opacity(0.95)
        static let textSecondary = SwiftUI.Color.white.opacity(0.62)
        static let textTertiary  = SwiftUI.Color.white.opacity(0.38)

        static let accent  = SwiftUI.Color(red: 0.0,  green: 0.85, blue: 1.0)         // #00D9FF cyan
        static let accent2 = SwiftUI.Color(red: 0.49, green: 0.23, blue: 0.93)        // #7C3AED violet
        static let success = SwiftUI.Color(red: 0.20, green: 0.83, blue: 0.60)        // #34D399 mint
        static let warn    = SwiftUI.Color(red: 0.98, green: 0.75, blue: 0.14)        // #FAC024 amber
        static let danger  = SwiftUI.Color(red: 0.94, green: 0.27, blue: 0.27)        // #EF4444 red
        static let info    = SwiftUI.Color(red: 0.40, green: 0.71, blue: 1.0)         // #66B5FF
    }

    enum Gradient {
        static let appBackground = LinearGradient(
            colors: [Color.bgDeep, Color.bgMid, Color.bgLift],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let neonHorizon = LinearGradient(
            colors: [Color.accent, Color.accent2],
            startPoint: .leading,
            endPoint: .trailing
        )

        static let successHorizon = LinearGradient(
            colors: [Color.success, Color.accent],
            startPoint: .leading,
            endPoint: .trailing
        )

        static let dangerHorizon = LinearGradient(
            colors: [Color.warn, Color.danger],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    enum Font {
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.Gradient.appBackground
                .ignoresSafeArea()

            // Soft accent glow blobs
            Circle()
                .fill(Theme.Color.accent.opacity(0.18))
                .frame(width: 440, height: 440)
                .blur(radius: 120)
                .offset(x: -180, y: -260)

            Circle()
                .fill(Theme.Color.accent2.opacity(0.16))
                .frame(width: 520, height: 520)
                .blur(radius: 140)
                .offset(x: 200, y: 320)

            // Subtle grid
            GridLines()
                .stroke(Color.white.opacity(0.025), lineWidth: 0.5)
                .ignoresSafeArea()
        }
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 36
        var x: CGFloat = 0
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y < rect.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return p
    }
}
