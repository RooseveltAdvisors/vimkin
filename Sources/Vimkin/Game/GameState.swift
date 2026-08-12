// GameState.swift — the adventure game's pure, testable core (plan U7).
//
// Owns a VimEngine over the level document, the trapped Vimkins, goal
// evaluation, the keystroke count against par, and completion. No SpriteKit, no
// SwiftUI, no persistence — the scene renders this, the session persists from
// it, and the tests drive it directly.
//
// Two structural guarantees this type is responsible for:
//
//  1. The LOCK GATE LIVES HERE, not in the view. `send(_:)` consults the
//     LockFilter itself and returns early on a block, so a locked key provably
//     cannot reach the engine even if a future UI forgets to pass the filter.
//  2. GOALS LATCH. Conditions like "the cursor reaches this cell" are transient
//     — the player walks on. A rescued Vimkin stays rescued.

import Foundation

/// What one key did.
public struct GameStep: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The key passed the gate and reached the engine.
        case delivered
        /// The key was locked; the engine never saw it.
        case blocked(reason: String)
    }

    public var outcome: Outcome
    /// Events the engine emitted (empty for a no-op or a blocked key).
    /// U8's juice layer keys its feedback tier off `CommandEvent.category`.
    public var events: [CommandEvent]
    /// Vimkins freed by THIS key (the rescue-pop trigger).
    public var newlyRescued: [Vimkin]
    /// True on the key that completed the level (and on none after it).
    public var justCompleted: Bool

    public var wasBlocked: Bool {
        if case .blocked = outcome { return true }
        return false
    }

    public var blockReason: String? {
        if case .blocked(let reason) = outcome { return reason }
        return nil
    }
}

public struct GameState: Equatable, Sendable {
    public let level: Level

    /// The engine over the level document — the single source of truth for text.
    public private(set) var engine: VimEngine
    /// The terrain the scene draws, mirrored from the engine after every key.
    /// The engine↔game sync invariant test pins this to `engine.buffer.lines`.
    public private(set) var documentLines: [String]
    /// Ids of Vimkins freed so far (latched).
    public private(set) var rescuedIDs: Set<String>
    /// Indices into `level.extraGoals` already satisfied (latched).
    public private(set) var satisfiedGoalIndices: Set<Int>
    /// Keys DELIVERED to the engine. Blocked keys never count — being gently
    /// stopped by a lock must never cost the player par.
    public private(set) var keystrokes: Int
    /// Latched: true from the moment every goal has been met.
    public private(set) var isComplete: Bool

    /// The skill gate. Read-only after construction — nothing can widen a
    /// level's toolkit mid-run.
    public let lockFilter: LockFilter

    // MARK: - Init

    public init(level: Level, lockFilter: LockFilter) {
        self.level = level
        self.engine = VimEngine(text: level.document)
        self.documentLines = TextBuffer(text: level.document).lines
        self.rescuedIDs = []
        self.satisfiedGoalIndices = []
        self.keystrokes = 0
        self.isComplete = false
        self.lockFilter = lockFilter
        // A level may open with a goal already satisfied (a `written` goal whose
        // text is present from the start would be authoring nonsense) — evaluate
        // once so state is consistent from key zero.
        _ = evaluate()
    }

    /// Convenience for a level with no gate (tests, sandbox play).
    public init(level: Level) {
        self.init(level: level, lockFilter: .open)
    }

    // MARK: - Input

    /// The gate's verdict for a key, without consuming it (the view's filter).
    public func decision(for key: KeyInput) -> KeyDecision {
        lockFilter.decision(for: key, awaitingLiteral: engine.isAwaitingLiteralKey)
    }

    /// Feeds one key: gate → engine → goal evaluation.
    @discardableResult
    public mutating func send(_ key: KeyInput) -> GameStep {
        if case .block(let reason) = decision(for: key) {
            return GameStep(
                outcome: .blocked(reason: reason),
                events: [],
                newlyRescued: [],
                justCompleted: false
            )
        }

        keystrokes += 1
        let events = engine.feed(key)
        documentLines = engine.buffer.lines

        let wasComplete = isComplete
        let freed = evaluate()
        return GameStep(
            outcome: .delivered,
            events: events,
            newlyRescued: freed,
            justCompleted: isComplete && !wasComplete
        )
    }

    /// Feeds a key string (Esc as `\u{1B}`), returning every step. Used by the
    /// beatability tests and the "show me" affordance.
    @discardableResult
    public mutating func send(keys: String) -> [GameStep] {
        keys.map { c in
            switch c {
            case "\u{1B}": return send(.escape)
            case "\n", "\r": return send(.enter)
            default: return send(.char(c))
            }
        }
    }

    // MARK: - Goal evaluation

    /// Re-checks every unmet condition against the current engine state,
    /// latching whatever is now satisfied. Returns the Vimkins freed this pass.
    private mutating func evaluate() -> [Vimkin] {
        var freed: [Vimkin] = []
        for vimkin in level.vimkins where !rescuedIDs.contains(vimkin.id) {
            if Self.isSatisfied(vimkin.condition, engine: engine) {
                rescuedIDs.insert(vimkin.id)
                freed.append(vimkin)
            }
        }
        for (index, goal) in level.extraGoals.enumerated()
        where !satisfiedGoalIndices.contains(index) {
            if Self.isSatisfied(goal, engine: engine) {
                satisfiedGoalIndices.insert(index)
            }
        }
        // Completion requires EVERY goal — Vimkins and extras alike.
        if rescuedIDs.count == level.vimkins.count,
           satisfiedGoalIndices.count == level.extraGoals.count {
            isComplete = true
        }
        return freed
    }

    /// Pure predicate: is this condition true of this engine state?
    public static func isSatisfied(_ condition: RescueCondition, engine: VimEngine) -> Bool {
        switch condition {
        case .cursorReaches(let position):
            return engine.cursor == position
        case .textRemoved(let text):
            return !engine.buffer.text.contains(text)
        case .textPresent(let text):
            return engine.buffer.text.contains(text)
        case .registerContains(let text):
            return engine.register?.text.contains(text) ?? false
        }
    }

    // MARK: - Derived view state

    public var rescuedCount: Int { rescuedIDs.count }
    public var totalVimkins: Int { level.vimkins.count }

    public func isRescued(_ vimkin: Vimkin) -> Bool { rescuedIDs.contains(vimkin.id) }

    /// Vimkins still trapped, in authoring order.
    public var remainingVimkins: [Vimkin] {
        level.vimkins.filter { !rescuedIDs.contains($0.id) }
    }

    /// Keystrokes over (positive) or under (negative) par.
    public var parDelta: Int { keystrokes - level.par }

    /// True while the run is still within par. Never gates completion — par is
    /// a flourish, not a failure condition (accuracy first, KTD 5).
    public var isUnderPar: Bool { keystrokes <= level.par }
}
