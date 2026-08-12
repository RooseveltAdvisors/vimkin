import CoreGraphics
import SpriteKit
import Testing
@testable import Vimkin

/// The SpriteKit renderer's half of the juice contract: the actions and
/// emitters it builds must read their numbers off the shared `JuiceEffectSpec`
/// rather than a private copy, and must clean up after themselves. Headless —
/// node graphs are inspected, nothing is drawn. (The spec's own numbers are
/// pinned by `JuiceEffectTests` — unit tier.)
@Suite("Juice: the SpriteKit backend follows the shared spec", .tags(.acceptance))
struct JuiceSpriteKitTests {

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
