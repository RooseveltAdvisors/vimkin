// GameSession.swift — the observable shell around GameState (plan U7).
//
// GameState is a pure value type; this is the thing SwiftUI watches and the
// thing that talks to persistence. It:
//   • routes keys through GameState (which owns the lock gate),
//   • records mastery reps + XP on the shared ProgressStore for delivered
//     commands (playing the game IS practice),
//   • records level results in the GameProgressStore on completion,
//   • surfaces the last blocked key so the view can shimmer + toast,
//   • exposes `onStep` — the single hook U8's juice layer subscribes to.
//
// Observation-only (no SwiftUI import), so it is fully testable headless.

import Foundation
import Observation

@MainActor
@Observable
public final class GameSession {

    // MARK: - Observable state

    public private(set) var state: GameState
    /// The most recent block, for the "you'll learn this in…" toast. Cleared by
    /// the view once shown.
    public private(set) var lastBlock: BlockedKey?
    /// Vimkins freed by the most recent key — the rescue-pop trigger.
    public private(set) var lastRescued: [Vimkin] = []
    /// Bumped on every delivered key, so views can drive animations off it.
    public private(set) var tick: Int = 0
    /// True once this run has been banked (completion is recorded exactly once).
    public private(set) var didRecordCompletion = false

    public struct BlockedKey: Equatable, Sendable {
        public let key: KeyInput
        public let reason: String
        /// Increments per block so an identical repeat still re-triggers the UI.
        public let sequence: Int
    }

    // MARK: - Dependencies

    public let level: Level
    private let progress: ProgressStore?
    private let gameProgress: GameProgressStore?
    private var blockSequence = 0

    /// Fired after every key. U8: particle/sound triggers hang here — the step
    /// carries the CommandEvents (category = juice tier), the newly rescued
    /// Vimkins, and the completion edge.
    @ObservationIgnored
    public var onStep: ((GameStep) -> Void)?

    // MARK: - Init

    public init(
        level: Level,
        database: CommandDatabase?,
        progress: ProgressStore? = nil,
        gameProgress: GameProgressStore? = nil
    ) {
        let filter: LockFilter
        if let database {
            filter = LockFilter.make(
                level: level,
                database: database,
                unlockedCommandIDs: progress?.unlockedCommands ?? []
            )
        } else {
            // No database → no gate. Never silently lock the player out.
            filter = .open
        }
        self.level = level
        self.state = GameState(level: level, lockFilter: filter)
        self.progress = progress
        self.gameProgress = gameProgress
    }

    // MARK: - Input

    @discardableResult
    public func send(_ key: KeyInput) -> GameStep {
        let step = state.send(key)

        switch step.outcome {
        case .blocked(let reason):
            blockSequence += 1
            lastBlock = BlockedKey(key: key, reason: reason, sequence: blockSequence)
        case .delivered:
            tick += 1
            lastRescued = step.newlyRescued
            record(step.events)
            if step.justCompleted { recordCompletion() }
        }

        onStep?(step)
        return step
    }

    /// Convenience for scripted play ("\u{1B}" = Esc).
    @discardableResult
    public func send(keys: String) -> [GameStep] {
        keys.map { c in
            switch c {
            case "\u{1B}": return send(.escape)
            case "\n", "\r": return send(.enter)
            default: return send(.char(c))
            }
        }
    }

    public func clearBlock() { lastBlock = nil }
    public func clearRescueFlash() { lastRescued = [] }

    /// Restart the level from scratch, keeping the same gate.
    public func restart() {
        state = GameState(level: level, lockFilter: state.lockFilter)
        lastBlock = nil
        lastRescued = []
        tick = 0
        didRecordCompletion = false
    }

    // MARK: - Persistence

    private func record(_ events: [CommandEvent]) {
        guard let progress else { return }
        for event in events {
            if let id = GameEventMapping.commandID(for: event) {
                progress.recordRep(commandID: id, outcome: .correct)
            }
            if let complexity = GameEventMapping.complexity(for: event) {
                progress.awardXP(for: complexity)
            }
        }
    }

    private func recordCompletion() {
        guard !didRecordCompletion else { return }
        didRecordCompletion = true
        gameProgress?.record(
            level: level,
            keystrokes: state.keystrokes,
            rescued: state.rescuedCount,
            completed: true
        )
    }
}
