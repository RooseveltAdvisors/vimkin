// IdleHint.swift — "you have been sitting here a while; here is the key."
//
// The gap this closes: a practice surface that names the JOB but not the KEY
// ("Start typing just after the cursor") leaves a beginner with nowhere to go.
// They do not always know a reveal exists, and in the Adventure there is no
// reveal at all. So after a quiet spell the app offers the key itself, once,
// gently, without ever being asked.
//
// Two pieces on purpose:
//
//   • `IdleHintTimer` — a pure value. All the timing rules live here, so they
//     are unit-testable with an injected clock and no waiting around.
//   • `IdleHintModel` — the observable shell a view watches, with a slow poll
//     driving it. It owns no rules; it only asks the timer.
//
// House rules for the copy that rides on this: never scolding, never a
// countdown, and it disappears the moment the player does anything.

import Foundation
import Observation

/// When a hint is due, as a pure function of "when did they last do something".
public struct IdleHintTimer: Equatable, Sendable {
    /// How long a surface stays quiet before the hint offers itself.
    public static let defaultDelay: TimeInterval = 8

    public let delay: TimeInterval
    public private(set) var lastActivity: Date
    /// True once the player has acted on this prompt; a hint that has been
    /// answered does not come back for the same drill.
    public private(set) var isArmed: Bool

    public init(delay: TimeInterval = defaultDelay, start: Date) {
        self.delay = delay
        self.lastActivity = start
        self.isArmed = true
    }

    /// The player pressed something. Resets the clock and re-arms.
    public mutating func noteActivity(at now: Date) {
        lastActivity = now
        isArmed = true
    }

    /// A new drill / step / level: everything starts over.
    public mutating func restart(at now: Date) {
        lastActivity = now
        isArmed = true
    }

    /// Stop offering until the next `noteActivity` or `restart`.
    public mutating func disarm() { isArmed = false }

    /// Has the surface been quiet long enough to offer the key?
    public func isDue(at now: Date) -> Bool {
        guard isArmed else { return false }
        return now.timeIntervalSince(lastActivity) >= delay
    }
}

/// The observable shell a SwiftUI surface binds to.
///
/// `begin()` starts a slow poll (the hint is not time-critical, and a coarse
/// tick keeps this off the render hot path); `end()` stops it. Both are safe to
/// call repeatedly.
@MainActor
@Observable
public final class IdleHintModel {
    /// True while the hint should be on screen.
    public private(set) var isDue = false

    @ObservationIgnored private var timer: IdleHintTimer
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private let interval: Duration

    public init(
        delay: TimeInterval = IdleHintTimer.defaultDelay,
        pollInterval: Duration = .milliseconds(500),
        now: Date = Date()
    ) {
        self.timer = IdleHintTimer(delay: delay, start: now)
        self.interval = pollInterval
    }

    deinit { poll?.cancel() }

    /// Start (or restart) watching. Call from `.task`.
    public func begin(now: Date = Date()) {
        timer.restart(at: now)
        isDue = false
        poll?.cancel()
        poll = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                self.refresh()
            }
        }
    }

    /// Stop watching and clear the hint.
    public func end() {
        poll?.cancel()
        poll = nil
        isDue = false
    }

    /// A key landed: hide the hint and restart the quiet spell.
    public func noteActivity(now: Date = Date()) {
        timer.noteActivity(at: now)
        isDue = false
    }

    /// The player read it (or moved on): stop offering until they act again.
    public func dismiss() {
        timer.disarm()
        isDue = false
    }

    private func refresh(now: Date = Date()) {
        let due = timer.isDue(at: now)
        if due != isDue { isDue = due }
    }
}
