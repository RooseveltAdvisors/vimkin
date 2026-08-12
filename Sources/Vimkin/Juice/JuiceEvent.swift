// JuiceEvent.swift — the vocabulary of the juice layer (plan U8, KTD 5).
//
// One graded ladder, three rungs:
//
//   whisper — you moved (a tick + a breath of glow)
//   pop     — you edited (a pitched pop + a puff of particles)
//   burst   — you spoke the grammar (`diw`, `ci"`): particles, flash, a short
//             eased screen shake and a beat of hit-stop
//
// The grading IS the pedagogy: composed grammar must feel disproportionately
// better than a bare motion, because that is the click we are teaching toward.
//
// Everything in this file is a pure value with no UI framework attached, so the
// SwiftUI renderer and the SpriteKit renderer read the SAME numbers and cannot
// drift apart. Colours travel as hex from assets/briefs/style-guide.md; each
// backend turns them into its own colour type.

import CoreGraphics
import Foundation

/// How loud a piece of feedback is. Ordered: `.whisper < .pop < .burst`.
public enum JuiceTier: Int, Comparable, CaseIterable, Sendable {
    case whisper = 0
    case pop = 1
    case burst = 2

    public static func < (lhs: JuiceTier, rhs: JuiceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One piece of feedback to render: which rung, how hard, and (optionally) where.
///
/// `position` is always nil out of the mapper — geometry belongs to whichever
/// renderer knows the coordinate space (the editor's cursor rect, or the scene's
/// node position), so it is attached late via `at(_:)`.
public struct JuiceEvent: Equatable, Sendable {
    public var tier: JuiceTier
    /// 0...1, clamped on construction.
    public var intensity: Double
    public var position: CGPoint?

    public init(tier: JuiceTier, intensity: Double, position: CGPoint? = nil) {
        self.tier = tier
        self.intensity = min(max(intensity, 0), 1)
        self.position = position
    }

    /// The same feedback, anchored at a point in the renderer's coordinate space.
    public func at(_ position: CGPoint?) -> JuiceEvent {
        JuiceEvent(tier: tier, intensity: intensity, position: position)
    }

    /// The same feedback, louder by `amount` (clamped at full).
    public func boosted(by amount: Double) -> JuiceEvent {
        JuiceEvent(tier: tier, intensity: intensity + amount, position: position)
    }

    /// The render numbers for this event — the tier's ceiling, scaled by intensity.
    public var effect: JuiceEffectSpec {
        tier.effect.scaled(by: intensity)
    }
}

/// The concrete render numbers behind a tier. Framework-free on purpose: the
/// SwiftUI modifier and `SpriteKitJuice` both consume this one value.
public struct JuiceEffectSpec: Equatable, Sendable {
    /// How many specks fly out.
    public var particleCount: Int
    /// How long a speck lives, in seconds.
    public var particleLifetime: TimeInterval
    /// Peak opacity of the tint wash over the surface.
    public var flashOpacity: Double
    /// How long the wash takes to fade out.
    public var flashDuration: TimeInterval
    /// Screen-shake amplitude in points. **Zero for every tier but `.burst`.**
    public var shakeAmplitude: Double
    /// Shake decay time; the plan pins this to the 0.1–0.3s band, eased out.
    public var shakeDuration: TimeInterval
    /// A beat of hit-stop before the world resumes. Burst only.
    public var hitStop: TimeInterval
    /// Style-guide palette colour, as 0xRRGGBB.
    public var tintHex: UInt32

    public init(
        particleCount: Int,
        particleLifetime: TimeInterval,
        flashOpacity: Double,
        flashDuration: TimeInterval,
        shakeAmplitude: Double,
        shakeDuration: TimeInterval,
        hitStop: TimeInterval,
        tintHex: UInt32
    ) {
        self.particleCount = particleCount
        self.particleLifetime = particleLifetime
        self.flashOpacity = flashOpacity
        self.flashDuration = flashDuration
        self.shakeAmplitude = shakeAmplitude
        self.shakeDuration = shakeDuration
        self.hitStop = hitStop
        self.tintHex = tintHex
    }

    /// Scales the visual weight by an intensity in 0...1 (values outside are
    /// clamped, so a boosted combo can never exceed its tier's ceiling).
    ///
    /// Durations are only lightly modulated — a shake that gets *shorter* as it
    /// gets weaker reads as one effect, not two — and the shake stays inside the
    /// 0.1–0.3s band whenever it happens at all.
    public func scaled(by intensity: Double) -> JuiceEffectSpec {
        let factor = min(max(intensity, 0), 1)
        var scaled = self
        scaled.particleCount = Int((Double(particleCount) * (0.35 + 0.65 * factor)).rounded())
        scaled.flashOpacity = flashOpacity * factor
        scaled.shakeAmplitude = shakeAmplitude * factor
        if shakeAmplitude > 0 {
            scaled.shakeDuration = min(max(shakeDuration * (0.7 + 0.3 * factor), 0.1), 0.3)
        }
        scaled.hitStop = hitStop * factor
        return scaled
    }
}

public extension JuiceTier {
    /// The tier's ceiling — what a full-intensity hit looks like.
    ///
    /// Tints are style-guide anchors: cyan for movement (the cursor-spirit's own
    /// glow), amber for an edit (Vimkin lantern-belly), leaf for the grammar
    /// click (success).
    var effect: JuiceEffectSpec {
        switch self {
        case .whisper:
            return JuiceEffectSpec(
                particleCount: 3,
                particleLifetime: 0.18,
                flashOpacity: 0.05,
                flashDuration: 0.12,
                shakeAmplitude: 0,
                shakeDuration: 0,
                hitStop: 0,
                tintHex: 0x7DE8D8 // cursor cyan
            )
        case .pop:
            return JuiceEffectSpec(
                particleCount: 10,
                particleLifetime: 0.35,
                flashOpacity: 0.12,
                flashDuration: 0.20,
                shakeAmplitude: 0,
                shakeDuration: 0,
                hitStop: 0,
                tintHex: 0xFFC46B // vimkin amber
            )
        case .burst:
            return JuiceEffectSpec(
                particleCount: 26,
                particleLifetime: 0.60,
                flashOpacity: 0.22,
                flashDuration: 0.30,
                shakeAmplitude: 6,
                shakeDuration: 0.22,
                hitStop: 0.06,
                tintHex: 0x8BD97A // success leaf
            )
        }
    }

    /// Short label, for debug overlays and test failure messages.
    var name: String {
        switch self {
        case .whisper: return "whisper"
        case .pop: return "pop"
        case .burst: return "burst"
        }
    }
}
