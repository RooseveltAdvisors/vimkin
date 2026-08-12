// SwiftUIJuiceModifier.swift — the SwiftUI half of the juice layer (plan U8).
//
// Renders a JuiceEvent over any SwiftUI surface (the editor, the dojo, the
// tutorial): a tint flash, a Canvas particle puff, and — for a `.burst` only —
// a short eased screen shake in a randomized direction.
//
// Why Canvas and not a Metal `.colorEffect`/`.layerEffect` shader: a `.metal`
// source file needs the Metal toolchain at build time, which a
// CommandLineTools-only machine does not have, and the project's zero-dependency
// rule rules out shipping a prebuilt metallib from elsewhere. `TimelineView` +
// `Canvas` is GPU-composited, costs nothing while idle (it only exists during a
// burst's lifetime), and keeps `swift build` green everywhere. The shader route
// stays open behind this same `JuiceEffectSpec`.
//
// Accessibility: Reduce Motion suppresses the shake (the flash and particles,
// which don't move the frame, remain).

import SwiftUI

public extension View {
    /// Renders the conductor's feedback over this view.
    func juice(_ conductor: JuiceConductor) -> some View {
        modifier(JuiceModifier(conductor: conductor))
    }
}

public struct JuiceModifier: ViewModifier {
    private let conductor: JuiceConductor

    @State private var shakeOffset: CGSize = .zero
    @State private var flashOpacity: Double = 0
    @State private var flashColor: Color = .clear
    @State private var burst: JuiceBurst?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(conductor: JuiceConductor) {
        self.conductor = conductor
    }

    public func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset.width, y: shakeOffset.height)
            .overlay {
                flashColor
                    .opacity(flashOpacity)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            .overlay {
                if let burst {
                    JuiceParticleField(burst: burst)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: conductor.pulse) { _, _ in
                guard let event = conductor.current else { return }
                render(event)
            }
            .task(id: burst?.id) {
                guard let burst else { return }
                let nanoseconds = UInt64(max(burst.spec.particleLifetime, 0.05) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                if self.burst?.id == burst.id { self.burst = nil }
            }
    }

    private func render(_ event: JuiceEvent) {
        let spec = event.effect

        // Flash — a wash of the tier's palette colour, eased out.
        flashColor = Color(hex: spec.tintHex)
        flashOpacity = spec.flashOpacity
        withAnimation(.easeOut(duration: spec.flashDuration)) { flashOpacity = 0 }

        // Shake — burst only, randomized direction, eased back to rest.
        if spec.shakeAmplitude > 0, !reduceMotion {
            let angle = Double.random(in: 0 ..< 2 * .pi)
            shakeOffset = CGSize(
                width: cos(angle) * spec.shakeAmplitude,
                height: sin(angle) * spec.shakeAmplitude
            )
            withAnimation(.easeOut(duration: spec.shakeDuration)) { shakeOffset = .zero }
        }

        // Particles.
        if spec.particleCount > 0 {
            burst = JuiceBurst(id: conductor.pulse, spec: spec, anchor: event.position, start: .now)
        }
    }
}

/// One live particle puff. Deterministic given its id — no per-frame randomness,
/// so a redraw never re-scrambles the specks mid-flight.
struct JuiceBurst: Equatable {
    let id: Int
    let spec: JuiceEffectSpec
    /// Anchor in the surface's own coordinate space; nil = centre.
    let anchor: CGPoint?
    let start: Date
}

/// The particle puff, drawn with Canvas inside a TimelineView so it animates
/// without a stored per-frame model. Alive only for the burst's lifetime.
struct JuiceParticleField: View {
    let burst: JuiceBurst

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, at: timeline.date)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, at date: Date) {
        let elapsed: Double = date.timeIntervalSince(burst.start)
        let lifetime: Double = max(burst.spec.particleLifetime, 0.01)
        let progress: Double = min(max(elapsed / lifetime, 0), 1)
        guard progress < 1 else { return }

        let origin: CGPoint = burst.anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let color = Color(hex: burst.spec.tintHex)
        let count: Int = max(burst.spec.particleCount, 1)
        // Eased travel: fast out, drifting to a stop.
        let travel: Double = 1 - pow(1 - progress, 3)
        let fade: Double = 1 - progress
        let reach: Double = 26 + 240 * burst.spec.flashOpacity
        // Deterministic spread: an even fan plus an id-derived phase, so two
        // bursts in a row don't look stamped from the same die — and a redraw
        // never re-scrambles specks mid-flight.
        let phase: Double = Double((burst.id &* 2_654_435_761) % 1_000) / 1_000

        context.opacity = fade
        for index in 0 ..< count {
            let angle: Double = (Double(index) / Double(count) + phase) * 2 * Double.pi
            let wobble: Double = 0.75 + 0.5 * Double((index &* 7) % 5) / 4
            let distance: Double = reach * travel * wobble
            let x: Double = origin.x + cos(angle) * distance
            let y: Double = origin.y + sin(angle) * distance
            let radius: Double = (1.6 + 1.8 * wobble) * (0.4 + 0.6 * fade)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
