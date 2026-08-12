// JuiceCombo.swift — the only stateful bit of the juice core (plan U8).
//
// A run of composed commands (`dw` → `ci"` → `diw`…) feels progressively
// better; a pause lets the run cool off. That's the whole model.
//
// Ethical-gamification constraints (plan R7 / KTD 5) baked into the rules:
//   • The combo only ever ADDS. There is no penalty state, no "combo broken"
//     sting, and a plain motion in the middle of a run costs nothing.
//   • Decay is time-based and gentle — you lose a step per quiet interval, not
//     the whole run the instant you pause to think.
//   • The boost is capped, so the ceiling of a `.burst` is a `.burst`; a long
//     run can never manufacture feedback the grading didn't earn.
//
// Value type with an injected clock (times are passed in), so a whole session
// is deterministic and testable without waiting on a real one.

import Foundation

public struct JuiceCombo: Sendable {
    public struct Configuration: Sendable {
        /// Longest run the boost counts.
        public var cap: Int
        /// Intensity added at a full run (leaves `.burst` topping out at 1.0).
        public var weight: Double
        /// Quiet seconds that shed one step of the run.
        public var decayInterval: TimeInterval

        public init(cap: Int = 8, weight: Double = 0.25, decayInterval: TimeInterval = 3.0) {
            self.cap = max(cap, 1)
            self.weight = max(weight, 0)
            self.decayInterval = max(decayInterval, 0.001)
        }
    }

    public let configuration: Configuration

    /// Length of the current run, already decayed to the last observed time.
    public private(set) var count: Int = 0

    private var lastEventTime: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// The intensity currently added to a hit by the run so far, 0...weight.
    public var bonus: Double {
        configuration.weight * Double(min(count, configuration.cap)) / Double(configuration.cap)
    }

    /// Ages the run forward to `time` without registering anything.
    public mutating func decay(to time: TimeInterval) {
        guard let last = lastEventTime, time > last else { return }
        let steps = Int((time - last) / configuration.decayInterval)
        if steps > 0 {
            count = max(0, count - steps)
            lastEventTime = time
        }
    }

    /// Registers one completed command and returns the feedback to render.
    ///
    /// Order matters and is deliberate: the run is aged first, the boost is
    /// taken from the run you had *coming in*, and only then does this command
    /// extend the run. So the first composed command after a long pause feels
    /// exactly like the mapper's base value — the reward is for the run, and it
    /// arrives on the second hit.
    @discardableResult
    public mutating func register(_ event: CommandEvent, at time: TimeInterval) -> JuiceEvent? {
        decay(to: time)
        lastEventTime = time

        guard let base = JuiceMapper.juice(for: event) else { return nil }
        let boosted = base.boosted(by: bonus)

        if JuiceMapper.isComposed(event) {
            count = min(count + 1, configuration.cap)
        }
        return boosted
    }

    /// Registers a batch (one `onEvents` delivery): every event advances the
    /// run, but only the loudest is rendered.
    @discardableResult
    public mutating func register(_ events: [CommandEvent], at time: TimeInterval) -> JuiceEvent? {
        events
            .compactMap { register($0, at: time) }
            .max { ($0.tier, $0.intensity) < ($1.tier, $1.intensity) }
    }

    /// Drops the run (used when a surface is torn down or a drill restarts).
    public mutating func reset() {
        count = 0
        lastEventTime = nil
    }
}
