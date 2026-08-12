// JuiceEffectTests — the render spec shared by both backends.
//
// SwiftUI view modifiers cannot reach inside an SKScene, so the juice layer has
// two renderers. They must not drift, which is why the numbers live in ONE pure
// value (`JuiceEffectSpec`) that both consume — and which is what these tests
// pin down.

import CoreGraphics
import SpriteKit
import Testing
@testable import Vimkin

@Suite("Juice: shared effect spec + SpriteKit factories")
struct JuiceEffectTests {
    @Test("screen shake happens on burst and ONLY on burst")
    func onlyBurstShakes() {
        #expect(JuiceTier.whisper.effect.shakeAmplitude == 0)
        #expect(JuiceTier.pop.effect.shakeAmplitude == 0)
        #expect(JuiceTier.burst.effect.shakeAmplitude > 0)

        // …at every intensity, not just at full.
        for intensity in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(JuiceEvent(tier: .whisper, intensity: intensity).effect.shakeAmplitude == 0)
            #expect(JuiceEvent(tier: .pop, intensity: intensity).effect.shakeAmplitude == 0)
        }
    }

    @Test("shake duration stays in the 0.1–0.3s band the plan specifies")
    func shakeDurationBand() {
        for intensity in stride(from: 0.0, through: 1.0, by: 0.05) {
            let effect = JuiceEvent(tier: .burst, intensity: intensity).effect
            #expect(effect.shakeDuration >= 0.1)
            #expect(effect.shakeDuration <= 0.3)
        }
    }

    @Test("hit-stop is reserved for the burst")
    func hitStopIsBurstOnly() {
        #expect(JuiceTier.whisper.effect.hitStop == 0)
        #expect(JuiceTier.pop.effect.hitStop == 0)
        #expect(JuiceTier.burst.effect.hitStop > 0)
    }

    @Test("louder tiers get more particles, more flash, longer life")
    func specsEscalateWithTier() {
        let whisper = JuiceTier.whisper.effect
        let pop = JuiceTier.pop.effect
        let burst = JuiceTier.burst.effect

        #expect(whisper.particleCount < pop.particleCount)
        #expect(pop.particleCount < burst.particleCount)
        #expect(whisper.flashOpacity < pop.flashOpacity)
        #expect(pop.flashOpacity < burst.flashOpacity)
        #expect(whisper.particleLifetime < burst.particleLifetime)
    }

    @Test("intensity scales an effect down but never past its tier ceiling")
    func intensityScalesWithinTheTierCeiling() {
        for tier in JuiceTier.allCases {
            let full = tier.effect
            let half = full.scaled(by: 0.5)
            let none = full.scaled(by: 0)

            #expect(half.particleCount <= full.particleCount)
            #expect(half.flashOpacity <= full.flashOpacity)
            #expect(half.shakeAmplitude <= full.shakeAmplitude)
            #expect(none.flashOpacity >= 0)
            #expect(full.scaled(by: 4).flashOpacity == full.flashOpacity) // clamped at 1
            #expect(full.tintHex == half.tintHex)
        }
    }

    @Test("every tier paints from the style-guide palette")
    func tintsComeFromTheStyleGuide() {
        let palette: Set<UInt32> = [0x7DE8D8, 0xFFC46B, 0x8BD97A] // cyan, amber, leaf
        for tier in JuiceTier.allCases {
            #expect(palette.contains(tier.effect.tintHex))
        }
    }

    // MARK: - SpriteKit backend

    @Test("the SpriteKit shake action exists only for a burst")
    @MainActor func spriteKitShakeIsBurstOnly() {
        #expect(SpriteKitJuice.shakeAction(for: JuiceEvent(tier: .whisper, intensity: 1)) == nil)
        #expect(SpriteKitJuice.shakeAction(for: JuiceEvent(tier: .pop, intensity: 1)) == nil)
        #expect(SpriteKitJuice.shakeAction(for: JuiceEvent(tier: .burst, intensity: 1)) != nil)
    }

    @Test("the SpriteKit hit-stop exists only for a burst")
    @MainActor func spriteKitHitStopIsBurstOnly() {
        #expect(SpriteKitJuice.hitStopAction(for: JuiceEvent(tier: .pop, intensity: 1)) == nil)
        #expect(SpriteKitJuice.hitStopAction(for: JuiceEvent(tier: .burst, intensity: 1)) != nil)
    }

    @Test("SpriteKit emitters read their numbers off the shared spec")
    @MainActor func spriteKitEmitterFollowsTheSpec() {
        for tier in JuiceTier.allCases {
            let event = JuiceEvent(tier: tier, intensity: 1)
            let emitter = SpriteKitJuice.emitter(for: event)
            #expect(emitter.numParticlesToEmit == event.effect.particleCount)
            // SpriteKit stores these as Float, hence the tolerance.
            #expect(abs(Double(emitter.particleLifetime) - event.effect.particleLifetime) < 1e-6)
        }
    }

    @Test("emit attaches a self-removing node to the parent at the requested point")
    @MainActor func emitAttachesAndCleansUp() {
        let parent = SKNode()
        let node = SpriteKitJuice.emit(JuiceEvent(tier: .burst, intensity: 1), at: CGPoint(x: 4, y: 9), in: parent)
        #expect(node.parent === parent)
        #expect(node.position == CGPoint(x: 4, y: 9))
        #expect(parent.children.count == 1)
        #expect(node.action(forKey: SpriteKitJuice.cleanupActionKey) != nil)
    }
}
