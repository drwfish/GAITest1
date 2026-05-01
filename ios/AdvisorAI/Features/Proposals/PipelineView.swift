import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Animated visualization of a proposal flowing through the pipeline:
/// Ingest → Validate → Signal → Optimize → Risk → Policy → Approval → OMS → Broker → Reconcile.
///
/// Lane labels indicate the AI advisory plane (the `signal` stage) vs the deterministic
/// execution plane (everything else).  The view is reusable and stateless w.r.t. AppState —
/// pass `haltAt:` to show a red failure stop.
struct PipelineView: View {

    // MARK: API

    let stages: [PipelineStage]
    let autoplay: Bool
    let haltAt: PipelineStage?
    let onComplete: (() -> Void)?

    /// Parents may bump this binding to replay the animation. Optional.
    @Binding var trigger: Int

    init(stages: [PipelineStage] = PipelineStage.allCases,
         autoplay: Bool = true,
         haltAt: PipelineStage? = nil,
         trigger: Binding<Int> = .constant(0),
         onComplete: (() -> Void)? = nil) {
        self.stages = stages
        self.autoplay = autoplay
        self.haltAt = haltAt
        self._trigger = trigger
        self.onComplete = onComplete
    }

    // MARK: Internal animation state

    @State private var activeIndex: Int = -1     // -1 = not started
    @State private var beamProgress: CGFloat = 0  // 0...Double(stages.count-1)
    @State private var particleProgress: CGFloat = 0
    @State private var failed: Bool = false
    @State private var lastTrigger: Int = -1

    // MARK: Layout constants

    private let nodeSize: CGFloat = 92
    private let compactNodeSize: CGFloat = 72
    private let nodeSpacing: CGFloat = 56
    private let laneTop: CGFloat = 8
    private let trackY: CGFloat = 64   // y-center of beam relative to node top

    private var stepDuration: Double { 0.6 }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let fits = canFitInline(width: geo.size.width)
            let size = fits ? compactNodeSize : nodeSize
            let spacing: CGFloat = fits ? max(28, (geo.size.width - size * CGFloat(stages.count)) / CGFloat(max(1, stages.count - 1))) : nodeSpacing
            let totalWidth = size * CGFloat(stages.count) + spacing * CGFloat(max(0, stages.count - 1))

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    laneLabels(nodeSize: size, spacing: spacing)
                        .padding(.top, 0)

                    track(nodeSize: size, spacing: spacing, totalWidth: totalWidth)
                        .padding(.top, laneTop + 28)

                    nodesRow(nodeSize: size, spacing: spacing)
                        .padding(.top, laneTop + 28)
                }
                .frame(width: max(totalWidth + 24, geo.size.width), alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDisabled(fits)
        }
        .frame(height: 220)
        .onAppear {
            if autoplay { play() }
        }
        .onChange(of: trigger) { _, newVal in
            guard newVal != lastTrigger else { return }
            lastTrigger = newVal
            play()
        }
    }

    // MARK: Lane labels

    @ViewBuilder
    private func laneLabels(nodeSize size: CGFloat, spacing: CGFloat) -> some View {
        // Build two pills: violet over the run of !isDeterministic stages, cyan over the deterministic run.
        // We compute spans by scanning the stages array.
        let spans = computeLaneSpans()
        ZStack(alignment: .topLeading) {
            ForEach(spans, id: \.start) { span in
                let x = CGFloat(span.start) * (size + spacing)
                let w = CGFloat(span.length) * size + CGFloat(max(0, span.length - 1)) * spacing
                lanePill(deterministic: span.deterministic)
                    .frame(width: w, alignment: .leading)
                    .offset(x: x, y: 0)
            }
        }
        .frame(height: 22, alignment: .topLeading)
    }

    private func lanePill(deterministic: Bool) -> some View {
        let tint = deterministic ? Theme.Color.accent : Theme.Color.accent2
        let label = deterministic ? "DETERMINISTIC EXECUTION PLANE" : "AI ADVISORY PLANE"
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(label)
                .font(Theme.Font.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.10))
        )
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.7)
        )
    }

    // MARK: Track + beam + particle

    @ViewBuilder
    private func track(nodeSize size: CGFloat, spacing: CGFloat, totalWidth: CGFloat) -> some View {
        let yCenter = size / 2
        let startX = size / 2
        let endX = totalWidth - size / 2
        let length = max(0, endX - startX)
        let beamLen = max(0, min(1, beamProgress / CGFloat(max(1, stages.count - 1)))) * length
        let particleX = startX + max(0, min(1, particleProgress / CGFloat(max(1, stages.count - 1)))) * length

        ZStack(alignment: .topLeading) {
            // base track
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: length, height: 3)
                .offset(x: startX, y: yCenter - 1.5)

            // beam overlay
            Capsule()
                .fill(failed ? Theme.Gradient.dangerHorizon : Theme.Gradient.neonHorizon)
                .frame(width: beamLen, height: 3)
                .offset(x: startX, y: yCenter - 1.5)
                .shadow(color: (failed ? Theme.Color.danger : Theme.Color.accent).opacity(0.7), radius: 8)

            // trail (faint)
            Capsule()
                .fill(LinearGradient(
                    colors: [Color.clear, (failed ? Theme.Color.danger : Theme.Color.accent).opacity(0.45)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, particleX - startX - 24), height: 8)
                .blur(radius: 6)
                .offset(x: startX, y: yCenter - 4)

            // particle
            Circle()
                .fill(failed ? Theme.Color.danger : Color.white)
                .frame(width: 9, height: 9)
                .overlay(
                    Circle()
                        .stroke((failed ? Theme.Color.danger : Theme.Color.accent), lineWidth: 1.5)
                )
                .shadow(color: (failed ? Theme.Color.danger : Theme.Color.accent), radius: 10)
                .offset(x: particleX - 4.5, y: yCenter - 4.5)
                .opacity(beamProgress > 0 ? 1 : 0)
        }
        .frame(height: size)
    }

    // MARK: Nodes row

    @ViewBuilder
    private func nodesRow(nodeSize size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(stages.enumerated()), id: \.element) { idx, stage in
                node(for: stage, index: idx, size: size)
            }
        }
    }

    @ViewBuilder
    private func node(for stage: PipelineStage, index idx: Int, size: CGFloat) -> some View {
        let state = nodeState(for: idx, stage: stage)
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(state.fillTint.opacity(state.glow ? 0.18 : 0.04))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(state.borderTint, lineWidth: state.glow ? 1.4 : 0.8)

                VStack(spacing: 4) {
                    Image(systemName: stage.icon)
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .foregroundStyle(state.iconTint)
                    Text(stage.title)
                        .font(Theme.Font.mono(10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(state.titleTint)
                }
                // checkmark when completed
                if state.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.success)
                        .background(Circle().fill(Theme.Color.bgMid))
                        .offset(x: size * 0.35, y: -size * 0.35)
                }
                // failure marker
                if state.failed {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.danger)
                        .background(Circle().fill(Theme.Color.bgMid))
                        .offset(x: size * 0.35, y: -size * 0.35)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(state.glow ? 1.06 : 1.0)
            .shadow(color: state.glow ? state.glowTint.opacity(0.7) : .clear,
                    radius: state.glow ? 18 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state.glow)

            Text(stage.subtitle)
                .font(Theme.Font.body(9))
                .foregroundStyle(Theme.Color.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: size + 18)
        }
        .frame(width: size + 18)
    }

    // MARK: State machine

    private struct NodeVisualState {
        var glow: Bool
        var completed: Bool
        var failed: Bool
        var iconTint: Color
        var titleTint: Color
        var borderTint: Color
        var fillTint: Color
        var glowTint: Color
    }

    private func nodeState(for index: Int, stage: PipelineStage) -> NodeVisualState {
        let isFailed = failed && index == failedIndex
        let isActive = index == activeIndex && !isFailed
        let isCompleted = index < activeIndex || (failed && index < failedIndex) || (activeIndex == stages.count - 1 && index == activeIndex && !failed && completedAll)
        if isFailed {
            return .init(glow: true, completed: false, failed: true,
                         iconTint: Theme.Color.danger,
                         titleTint: Theme.Color.danger,
                         borderTint: Theme.Color.danger.opacity(0.8),
                         fillTint: Theme.Color.danger,
                         glowTint: Theme.Color.danger)
        }
        if isActive {
            return .init(glow: true, completed: false, failed: false,
                         iconTint: Theme.Color.accent,
                         titleTint: Theme.Color.textPrimary,
                         borderTint: Theme.Color.accent,
                         fillTint: Theme.Color.accent,
                         glowTint: Theme.Color.accent)
        }
        if isCompleted {
            return .init(glow: false, completed: true, failed: false,
                         iconTint: Theme.Color.success,
                         titleTint: Theme.Color.textPrimary,
                         borderTint: Theme.Color.success.opacity(0.45),
                         fillTint: Theme.Color.success,
                         glowTint: Theme.Color.success)
        }
        return .init(glow: false, completed: false, failed: false,
                     iconTint: Theme.Color.textTertiary,
                     titleTint: Theme.Color.textSecondary,
                     borderTint: Theme.Color.surfaceStroke,
                     fillTint: .white,
                     glowTint: .clear)
    }

    @State private var completedAll: Bool = false
    private var failedIndex: Int {
        guard let halt = haltAt, let idx = stages.firstIndex(of: halt) else { return -1 }
        return idx
    }

    // MARK: Animation driver

    private func play() {
        // reset
        withAnimation(.easeInOut(duration: 0.25)) {
            activeIndex = -1
            beamProgress = 0
            particleProgress = 0
            failed = false
            completedAll = false
        }
        // Step through stages
        let haltIdx: Int = failedIndex
        for i in 0..<stages.count {
            let delay = Double(i) * stepDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if haltIdx >= 0 && i > haltIdx { return }   // do not advance past halt
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    activeIndex = i
                }
                // beam fills toward this index
                withAnimation(.easeInOut(duration: stepDuration)) {
                    beamProgress = CGFloat(i)
                    particleProgress = CGFloat(i)
                }
                triggerHaptic()

                if haltIdx >= 0 && i == haltIdx {
                    DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * 0.5) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            failed = true
                        }
                    }
                }
            }
        }
        // finalize
        let totalTime = Double(stages.count) * stepDuration + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime) {
            if haltIdx < 0 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    completedAll = true
                }
                onComplete?()
            }
        }
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }

    // MARK: Helpers

    private func canFitInline(width: CGFloat) -> Bool {
        // iPad-ish width — fit inline with smaller nodes.
        let needed = compactNodeSize * CGFloat(stages.count) + 28 * CGFloat(max(0, stages.count - 1)) + 24
        return width >= needed
    }

    private struct LaneSpan {
        let start: Int
        let length: Int
        let deterministic: Bool
    }

    private func computeLaneSpans() -> [LaneSpan] {
        var spans: [LaneSpan] = []
        var i = 0
        while i < stages.count {
            let det = stages[i].isDeterministic
            var j = i
            while j < stages.count && stages[j].isDeterministic == det { j += 1 }
            spans.append(LaneSpan(start: i, length: j - i, deterministic: det))
            i = j
        }
        return spans
    }
}

#Preview {
    ZStack {
        AppBackground()
        PipelineView()
            .padding()
    }
}
