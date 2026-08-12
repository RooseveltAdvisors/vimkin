// DrillModels.swift — the value types the practice dojo (plan U6) is built on.
// Pure Swift + Foundation: no SwiftUI, no AppKit. Everything here is
// deterministic and directly testable.
//
// Accuracy-first rule (plan KTD 5): nothing in this file models a deadline, a
// countdown, or a failure-by-slowness. Elapsed time exists only as a rep
// classifier (`.correct` vs `.slowCorrect`) recorded in the mastery store.

import Foundation

// MARK: - Engine state snapshots

/// An engine state snapshot a drill is judged against. Captured before the
/// attempt and after it, so a drill's success rule reads only values (never a
/// live engine).
public struct DrillState: Equatable, Sendable {
    public let text: String
    public let cursor: Position
    public let mode: Mode
    public let register: Register?

    public init(text: String, cursor: Position, mode: Mode, register: Register?) {
        self.text = text
        self.cursor = cursor
        self.mode = mode
        self.register = register
    }

    public init(engine: VimEngine) {
        self.init(
            text: engine.buffer.text,
            cursor: engine.cursor,
            mode: engine.mode,
            register: engine.register
        )
    }

    public init(session: EditorSession) {
        self.init(engine: session.engine)
    }
}

/// One judged attempt: the events a single completed command emitted, plus the
/// before/after states around it.
public struct DrillAttempt: Equatable, Sendable {
    public let events: [CommandEvent]
    public let before: DrillState
    public let after: DrillState

    public init(events: [CommandEvent], before: DrillState, after: DrillState) {
        self.events = events
        self.before = before
        self.after = after
    }
}

// MARK: - Goals

/// The end state that identifies one command having been executed — the
/// data-driven form of a success predicate over (events, before, after).
///
/// Built by *simulating* the target command from the drill's start state, so a
/// goal can never describe an impossible outcome (see `DrillSiteFinder`).
public struct DrillGoal: Equatable, Sendable {
    /// Full buffer text after the command.
    public let text: String
    /// Cursor after the command.
    public let cursor: Position
    /// Mode after the command (`ci"` lands in insert, `w` stays in normal).
    public let mode: Mode
    /// Complexity class the command must emit — this is what separates `diw`
    /// (`.fullGrammar`) from `dw` (`.operatorMotion`) even when the two happen
    /// to leave identical text.
    public let category: CommandEvent.Category?
    /// Unnamed register contents after the command, when it is load-bearing
    /// (delete/change/yank drills). `nil` means "don't care".
    public let register: Register?

    public init(
        text: String,
        cursor: Position,
        mode: Mode,
        category: CommandEvent.Category?,
        register: Register?
    ) {
        self.text = text
        self.cursor = cursor
        self.mode = mode
        self.category = category
        self.register = register
    }

    /// The goal describing a simulated end state.
    public static func describing(
        _ state: DrillState,
        category: CommandEvent.Category?,
        includeRegister: Bool
    ) -> DrillGoal {
        DrillGoal(
            text: state.text,
            cursor: state.cursor,
            mode: state.mode,
            category: category,
            register: includeRegister ? state.register : nil
        )
    }

    /// The success predicate. A drill is solved by ONE completed command whose
    /// end state matches — a batch with no events is never a solution (partial
    /// input like a bare `d` is silent, and silence is not a wrong answer).
    public func matches(_ attempt: DrillAttempt) -> Bool {
        guard !attempt.events.isEmpty else { return false }
        guard attempt.after.text == text,
              attempt.after.cursor == cursor,
              attempt.after.mode == mode
        else { return false }
        if let category, !attempt.events.contains(where: { $0.category == category }) {
            return false
        }
        if let register, attempt.after.register != register { return false }
        return true
    }
}

// MARK: - Near misses

/// A recognized related-but-wrong command, so feedback can name the difference
/// instead of saying "wrong".
public struct NearMiss: Equatable, Sendable {
    /// What the learner actually executed, e.g. `"dw"`.
    public let performedKeys: String
    /// What the drill asked for, e.g. `"diw"`.
    public let targetKeys: String
    /// One sentence naming BOTH commands and how they differ.
    public let feedback: String

    public init(performedKeys: String, targetKeys: String, feedback: String) {
        self.performedKeys = performedKeys
        self.targetKeys = targetKeys
        self.feedback = feedback
    }
}

/// A confusable command precomputed for one drill site: its simulated end
/// state plus the sentence to show if the learner lands on it.
public struct NearMissCandidate: Equatable, Sendable {
    public let performedKeys: String
    public let outcome: DrillGoal
    public let feedback: String

    public init(performedKeys: String, outcome: DrillGoal, feedback: String) {
        self.performedKeys = performedKeys
        self.outcome = outcome
        self.feedback = feedback
    }
}

/// The verdict on one attempt. There is deliberately no "too slow" case.
public enum DrillJudgement: Equatable, Sendable {
    case correct
    case nearMiss(NearMiss)
    case incorrect(hint: String)

    public var isCorrect: Bool { self == .correct }

    /// The sentence to show the learner (empty for a correct attempt).
    public var message: String {
        switch self {
        case .correct: return ""
        case .nearMiss(let miss): return miss.feedback
        case .incorrect(let hint): return hint
        }
    }
}

// MARK: - Drill

/// One drill: a real corpus document, a concrete starting cursor, a plain
/// English instruction, the success rule, and the near-miss classifier.
public struct Drill: Identifiable, Equatable, Sendable {
    public let id: String
    /// `VimCommand.id` of the target command.
    public let commandID: String
    /// The command's canonical keys as shown to the learner, e.g. `"diw"`.
    public let commandKeys: String
    /// The exact keystrokes that solve THIS drill (find drills carry their
    /// argument, e.g. `"fb"`). Used by hints and by the solvability test.
    public let solutionKeys: String
    public let documentName: String
    public let documentText: String
    public let start: Position
    /// Plain English, e.g. "Delete the word `barrels` on line 12."
    public let instruction: String
    public let goal: DrillGoal
    public let nearMisses: [NearMissCandidate]

    public init(
        id: String,
        commandID: String,
        commandKeys: String,
        solutionKeys: String,
        documentName: String,
        documentText: String,
        start: Position,
        instruction: String,
        goal: DrillGoal,
        nearMisses: [NearMissCandidate]
    ) {
        self.id = id
        self.commandID = commandID
        self.commandKeys = commandKeys
        self.solutionKeys = solutionKeys
        self.documentName = documentName
        self.documentText = documentText
        self.start = start
        self.instruction = instruction
        self.goal = goal
        self.nearMisses = nearMisses
    }

    /// The success predicate over (events, before-state, after-state).
    public func succeeds(_ attempt: DrillAttempt) -> Bool {
        goal.matches(attempt)
    }

    /// The near-miss classifier: recognizes a related-but-wrong command.
    /// Only consulted after `succeeds` returns false.
    public func nearMiss(for attempt: DrillAttempt) -> NearMiss? {
        guard !attempt.events.isEmpty else { return nil }
        guard let candidate = nearMisses.first(where: { $0.outcome.matches(attempt) }) else {
            return nil
        }
        return NearMiss(
            performedKeys: candidate.performedKeys,
            targetKeys: commandKeys,
            feedback: candidate.feedback
        )
    }

    /// Judge one completed command. Correct → near-miss → gentle generic.
    public func evaluate(_ attempt: DrillAttempt) -> DrillJudgement {
        if succeeds(attempt) { return .correct }
        if let miss = nearMiss(for: attempt) { return .nearMiss(miss) }
        return .incorrect(hint: genericHint)
    }

    /// Gentle, never punitive: restate the goal and name the keys.
    public var genericHint: String {
        "Not quite — that wasn't `\(commandKeys)`. \(instruction) Give it another go."
    }
}
