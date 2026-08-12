// SpriteKitJuice.swift — the SpriteKit half of the juice layer (plan U8).
//
// SwiftUI view modifiers cannot reach inside an `SKScene`, so the game surface
// gets its own renderer. Both backends read the SAME `JuiceEffectSpec`, so the
// editor and the game can never disagree about what a `ci"` feels like.
//
// This file provides FACTORIES ONLY — it never instantiates or touches a game
// scene (U7 owns those). A scene calls:
//
//     SpriteKitJuice.emit(juice, at: node.position, in: self)
//     if let shake = SpriteKitJuice.shakeAction(for: juice) { camera.run(shake) }
//     if let stop  = SpriteKitJuice.hitStopAction(for: juice) { world.run(stop) }
//
// No .sks files and no image assets: the particle texture is drawn in code, so
// the layer works before a single generated asset lands.

import CoreGraphics
import Foundation
import SpriteKit

@MainActor
public enum SpriteKitJuice {
    /// Key on the auto-removal action attached to every emitted node.
    public static let cleanupActionKey = "vimkin.juice.cleanup"

    // MARK: - Emitting

    /// Emits a puff for `event` at `point` in `parent`, and returns the node.
    /// The node removes itself once the particles have died.
    @discardableResult
    public static func emit(_ event: JuiceEvent, at point: CGPoint, in parent: SKNode) -> SKNode {
        let emitter = emitter(for: event)
        emitter.position = point
        emitter.zPosition = 900
        parent.addChild(emitter)

        let lifetime = event.effect.particleLifetime
        emitter.run(
            .sequence([.wait(forDuration: lifetime * 2 + 0.2), .removeFromParent()]),
            withKey: cleanupActionKey
        )
        return emitter
    }

    /// Convenience for callers holding a tier rather than an event.
    @discardableResult
    public static func emit(
        tier: JuiceTier,
        at point: CGPoint,
        in parent: SKNode,
        intensity: Double = 1.0
    ) -> SKNode {
        emit(JuiceEvent(tier: tier, intensity: intensity), at: point, in: parent)
    }

    /// A configured emitter for the event's tier + intensity (unparented).
    public static func emitter(for event: JuiceEvent) -> SKEmitterNode {
        let spec = event.effect
        let emitter = SKEmitterNode()
        emitter.particleTexture = sparkTexture
        emitter.particleBirthRate = 900
        emitter.numParticlesToEmit = spec.particleCount
        emitter.particleLifetime = CGFloat(spec.particleLifetime)
        emitter.particleLifetimeRange = CGFloat(spec.particleLifetime * 0.4)
        emitter.particlePositionRange = CGVector(dx: 4, dy: 4)
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = CGFloat(40 + 90 * event.intensity)
        emitter.particleSpeedRange = CGFloat(30 * event.intensity)
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.6
        emitter.particleScale = CGFloat(0.10 + 0.14 * event.intensity)
        emitter.particleScaleRange = 0.06
        emitter.particleScaleSpeed = -0.16
        emitter.particleColor = color(spec.tintHex)
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        return emitter
    }

    /// Convenience for callers holding a tier rather than an event.
    public static func emitter(for tier: JuiceTier, intensity: Double = 1.0) -> SKEmitterNode {
        emitter(for: JuiceEvent(tier: tier, intensity: intensity))
    }

    // MARK: - Screen effects

    /// The eased screen shake — **nil for every tier but `.burst`**. Run it on
    /// the camera (or the world node) and it returns to rest by itself.
    public static func shakeAction(for event: JuiceEvent) -> SKAction? {
        let spec = event.effect
        guard spec.shakeAmplitude > 0, spec.shakeDuration > 0 else { return nil }

        let steps = 6
        let stepDuration = spec.shakeDuration / Double(steps)
        var actions: [SKAction] = []
        let angle = Double.random(in: 0 ..< 2 * .pi)

        for step in 0 ..< steps {
            // Decaying amplitude, alternating side — "kick and settle".
            let decay = 1 - Double(step) / Double(steps)
            let sign: Double = step.isMultiple(of: 2) ? 1 : -1
            let amplitude = spec.shakeAmplitude * decay * sign
            let move = SKAction.moveBy(
                x: CGFloat(cos(angle) * amplitude),
                y: CGFloat(sin(angle) * amplitude),
                duration: stepDuration
            )
            move.timingMode = .easeOut
            actions.append(move)
            actions.append(move.reversed())
        }
        return .sequence(actions)
    }

    /// A beat of hit-stop for the grammar click — nil below `.burst`.
    /// Run it on the node whose `speed` should stall (the world/scene).
    public static func hitStopAction(for event: JuiceEvent) -> SKAction? {
        let stop = event.effect.hitStop
        guard stop > 0 else { return nil }
        return .sequence([
            .speed(to: 0.0001, duration: 0),
            .wait(forDuration: stop),
            .speed(to: 1, duration: 0.05),
        ])
    }

    /// The tint wash for a tier, sized to a scene — the SpriteKit twin of the
    /// SwiftUI flash. Nil when the tier does not flash.
    public static func flashNode(for event: JuiceEvent, size: CGSize) -> SKNode? {
        let spec = event.effect
        guard spec.flashOpacity > 0 else { return nil }
        let node = SKSpriteNode(color: color(spec.tintHex), size: size)
        node.alpha = CGFloat(spec.flashOpacity)
        node.blendMode = .add
        node.zPosition = 950
        node.run(
            .sequence([
                .fadeOut(withDuration: spec.flashDuration),
                .removeFromParent(),
            ]),
            withKey: cleanupActionKey
        )
        return node
    }

    /// A scale "pop" for the thing that was acted on (a rescued Vimkin, a
    /// cleared bramble). Available at every tier, sized by the spec.
    public static func popAction(for event: JuiceEvent) -> SKAction {
        let amount = 1 + 0.06 + 0.14 * event.intensity * Double(event.tier.rawValue + 1) / 3
        let up = SKAction.scale(to: CGFloat(amount), duration: 0.06)
        up.timingMode = .easeOut
        let down = SKAction.scale(to: 1, duration: 0.12)
        down.timingMode = .easeOut
        return .sequence([up, down])
    }

    // MARK: - Palette + texture

    /// Style-guide hex → SpriteKit colour.
    public static func color(_ hex: UInt32) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A soft round speck, drawn in code so the layer needs no image assets.
    private static let sparkTexture: SKTexture? = makeSparkTexture()

    private static func makeSparkTexture(size: Int = 32) -> SKTexture? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let centre = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!,
                CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0])!,
            ] as CFArray,
            locations: [0, 1]
        ) else { return nil }

        context.drawRadialGradient(
            gradient,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: Double(size) / 2,
            options: []
        )
        guard let image = context.makeImage() else { return nil }
        return SKTexture(cgImage: image)
    }
}
