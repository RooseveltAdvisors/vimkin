// FeedbackViews.swift — the SwiftUI half of the practice-feedback layer.
//
//   KeyPressVisualizer  the big key-cap that punches in on every press, cyan
//                       when it was right, coral and wobbling when it wasn't —
//                       plus the chord chip row that shows `d` → `di` → `diw`
//                       BUILDING, which is the whole grammar made visible
//   Wobble              a short horizontal shake for a wrong attempt (gentle;
//                       nothing in this app is punitive)
//
// Reduce Motion is honoured: the wobble and the punch collapse to a fade.

import SwiftUI

// MARK: - Wobble

/// A short horizontal shake, driven by an animatable phase.
struct WobbleEffect: GeometryEffect {
    var phase: CGFloat
    var amplitude: CGFloat = 7
    var shakes: CGFloat = 3

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Envelope decays so it settles rather than stopping dead.
        let decay = max(0, 1 - phase)
        let offset = amplitude * decay * sin(phase * .pi * shakes * 2)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

private struct WobbleModifier: ViewModifier {
    let trigger: Int
    var amplitude: CGFloat = 7

    @State private var phase: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(WobbleEffect(phase: phase, amplitude: amplitude))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                phase = 0
                withAnimation(.easeOut(duration: 0.42)) { phase = 1 }
            }
    }
}

extension View {
    /// Shakes this view once, briefly, every time `trigger` changes.
    func wobble(trigger: Int, amplitude: CGFloat = 7) -> some View {
        modifier(WobbleModifier(trigger: trigger, amplitude: amplitude))
    }
}

// MARK: - Key-press visualiser

/// The big key-cap + the chord chip row.
struct KeyPressVisualizer: View {
    let hub: KeyFeedbackHub
    /// Where the row sits relative to the cap.
    var alignment: HorizontalAlignment = .trailing

    @State private var capScale: Double = 1
    @State private var capOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            chordRow
            keyCap
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hub.chord)
        .allowsHitTesting(false)
    }

    // MARK: Cap

    private var tint: Color {
        switch hub.latest?.verdict {
        case .wrong: return EditorTheme.coral
        case .right: return EditorTheme.leaf
        case .neutral, nil: return EditorTheme.cursor
        }
    }

    @ViewBuilder
    private var keyCap: some View {
        if let stroke = hub.latest {
            Text(stroke.label)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(tint)
                .frame(minWidth: 62, minHeight: 62)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.65), lineWidth: 2)
                )
                .shadow(color: tint.opacity(0.5), radius: 16)
                .scaleEffect(capScale)
                .opacity(capOpacity)
                .wobble(trigger: hub.wobble, amplitude: 9)
                .onChange(of: stroke.id) { _, _ in punch() }
                .onChange(of: stroke.verdict) { _, verdict in
                    guard verdict == .wrong, !reduceMotion else { return }
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.4)) { capScale = 1.18 }
                    withAnimation(.easeOut(duration: 0.3).delay(0.06)) { capScale = 1 }
                }
                .onAppear { punch() }
                .task(id: stroke.id) {
                    try? await Task.sleep(nanoseconds: 620_000_000)
                    withAnimation(.easeOut(duration: 0.30)) { capOpacity = 0 }
                }
        }
    }

    private func punch() {
        withAnimation(nil) {
            capScale = reduceMotion ? 1 : 1.8
            capOpacity = 1
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.46)) { capScale = 1 }
    }

    // MARK: Chord row

    @ViewBuilder
    private var chordRow: some View {
        if hub.chord.count > 1 || (hub.chordIsBuilding && !hub.chord.isEmpty) {
            HStack(spacing: 5) {
                ForEach(Array(hub.chord.enumerated()), id: \.offset) { index, key in
                    ChordChip(label: key, settled: !hub.chordIsBuilding)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .zIndex(Double(index))
                }
                if hub.chordIsBuilding {
                    PendingDots()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(EditorTheme.background.opacity(0.85))
            )
            .overlay(
                Capsule().strokeBorder(
                    (hub.chordIsBuilding ? EditorTheme.amber : EditorTheme.leaf).opacity(0.5),
                    lineWidth: 1.5
                )
            )
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }
}

/// One key in the chord row.
private struct ChordChip: View {
    let label: String
    let settled: Bool

    var body: some View {
        let tint = settled ? EditorTheme.leaf : EditorTheme.amber
        Text(label)
            .font(.system(size: 17, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .frame(minWidth: 22)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(0.55), lineWidth: 1))
    }
}

/// "the engine is still waiting" — three breathing dots.
private struct PendingDots: View {
    @State private var lit = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(EditorTheme.amber.opacity(lit ? 0.85 : 0.25))
                    .frame(width: 4, height: 4)
                    .animation(
                        .easeInOut(duration: 0.42).repeatForever().delay(Double(index) * 0.12),
                        value: lit
                    )
            }
        }
        .onAppear { lit = true }
    }
}

// MARK: - Ghost legend

/// The caption that introduces an outcome preview ("try one — each lands
/// somewhere different"). The ghosts themselves are drawn in the editor.
struct GhostLegend: View {
    let caption: String
    let ghosts: [OutcomeGhost]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .foregroundStyle(EditorTheme.amber)
            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(EditorTheme.text.opacity(0.75))
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(ghosts) { ghost in
                    Text(KeyGlyph.label(forKeys: ghost.keys))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(EditorTheme.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(EditorTheme.badgeColor(for: ghost.mode).opacity(0.9))
                        )
                }
            }
        }
    }
}
