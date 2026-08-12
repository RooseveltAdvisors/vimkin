// JuiceConductor.swift — the one object a surface owns to get juice (plan U8).
//
// It sits between `EditorSession.onEvents` (the engine's event firehose) and the
// two renderers: it runs the pure mapper + combo tracker, plays the sound, and
// publishes the current JuiceEvent for the SwiftUI modifier to animate. A
// SpriteKit scene can read the same `current` value and call `SpriteKitJuice`.
//
// Attaching is non-destructive: `attach(to:)` CHAINS onto whatever closure the
// surface's own model already installed (the dojo judges drills through that
// same hook), so juice can never eat a drill judgement.

import Foundation
import Observation

@MainActor
@Observable
public final class JuiceConductor {
    /// The most recent piece of feedback (nil until the first command).
    public private(set) var current: JuiceEvent?
    /// Increments on every emitted event — the animation trigger. (Two identical
    /// bursts in a row must still fire twice, which a value-change alone won't do.)
    public private(set) var pulse: Int = 0

    /// Sound. Nil = visuals only.
    @ObservationIgnored public var audio: JuiceAudio?
    @ObservationIgnored private var combo: JuiceCombo
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private weak var attachedSession: EditorSession?

    public init(
        audio: JuiceAudio? = nil,
        combo: JuiceCombo = JuiceCombo(),
        clock: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.audio = audio
        self.combo = combo
        self.clock = clock
    }

    /// Length of the current composed-command run.
    public var comboCount: Int { combo.count }

    // MARK: - Consuming engine events

    public func consume(_ events: [CommandEvent]) {
        guard !events.isEmpty else { return }
        guard let juice = combo.register(events, at: clock()) else { return }
        emit(juice)
    }

    public func consume(_ event: CommandEvent) {
        consume([event])
    }

    /// Renders a piece of feedback directly (celebrations, level completion —
    /// moments that don't come from a keystroke).
    public func emit(_ juice: JuiceEvent) {
        current = juice
        pulse &+= 1
        audio?.play(juice)
    }

    // MARK: - Wiring

    /// Chains juice onto a session's event hook, preserving any existing
    /// consumer. Idempotent per session, so it is safe to call from a SwiftUI
    /// `task(id:)` that may re-run.
    public func attach(to session: EditorSession) {
        guard attachedSession !== session else { return }
        attachedSession = session

        let existing = session.onEvents
        session.onEvents = { [weak self] events in
            existing?(events)
            MainActor.assumeIsolated { self?.consume(events) }
        }
    }

    /// Forgets the current run (surface teardown, drill restart).
    public func reset() {
        combo.reset()
        current = nil
        attachedSession = nil
    }
}
