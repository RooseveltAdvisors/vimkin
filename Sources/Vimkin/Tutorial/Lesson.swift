// Lesson.swift — the tutorial's data model (plan U5).
//
// A lesson teaches ONE idea, grammar-framed ("`d` is a verb, `w` is a noun,
// together `dw` deletes a word"), then drills it as a sequence of single-command
// steps. Lessons are authored as DATA (`Content/lessons.json`) so the curriculum
// is editable without touching Swift, and so a schema test can prove every
// target command still exists in the command database.
//
// Pure Swift + Foundation: no engine mutation, no UI. The runner (LessonRunner)
// evaluates these definitions; the SwiftUI layer only renders them.

import Foundation

/// One tutorial lesson: a concept card plus its drill steps.
public struct Lesson: Codable, Equatable, Sendable, Identifiable {
    /// Stable slug, e.g. `"t3-delete-verb"`.
    public let id: String
    /// Curriculum stage 1-5, matching `VimCommand.tier`.
    public let tier: Int
    /// Position within the tier (1-based, contiguous — pinned by a schema test).
    public let order: Int
    public let title: String
    /// The concept card: ONE idea, framed as grammar.
    public let concept: String
    /// The practice document every step opens (unless the step overrides it).
    /// Short, original, notes-flavored — never code.
    public let document: String
    /// Command ids this lesson teaches. Completing the lesson marks each of
    /// these complete in the ProgressStore, which is what unlocks them.
    public let teaches: [String]
    public let steps: [LessonStep]

    /// Sort key: tier first, then order.
    public var curriculumIndex: (Int, Int) { (tier, order) }
}

/// One drilled command inside a lesson. Exactly one command per step — a step is
/// judged against a single completed `CommandEvent`, never a key sequence.
public struct LessonStep: Codable, Equatable, Sendable, Identifiable {
    /// Stable slug, unique within the lesson.
    public let id: String
    /// What the learner is asked to do, in plain language.
    public let instruction: String
    /// The `VimCommand.id` this step drills (must exist and be engineSupported).
    public let targetCommandID: String
    /// Keys that solve the step from the prepared state. Used by the
    /// completability test (proof the authored content actually works) and by
    /// the "show me" affordance.
    public let canonicalKeys: String
    /// Practice document override; defaults to the lesson's document.
    public let document: String?
    /// Keys fed after (re)loading the document to place the learner where the
    /// step makes sense (e.g. `"jjw"` to sit on the word to delete). NOT judged.
    public let setupKeys: String?
    /// What counts as a correct rep.
    public let success: SuccessCriteria
    /// Shown after a wrong attempt. Gentle, never punitive.
    public let hint: String
    /// Correct reps needed to clear the step (nil → `LessonRunner.defaultRequiredReps`).
    public let requiredReps: Int?

    /// Effective rep requirement.
    public var reps: Int { max(1, requiredReps ?? LessonRunner.defaultRequiredReps) }

    /// The document this step practices on.
    public func documentText(in lesson: Lesson) -> String { document ?? lesson.document }
}

// MARK: - Success criteria

/// A declarative, JSON-authorable predicate over
/// (emitted CommandEvents, engine state before, engine state after).
///
/// Every field is optional; a nil field imposes no constraint. Event-level
/// fields must all be satisfied by the SAME emitted event (so `c` — which emits
/// a change event AND an enterInsert event — is matched on the change event,
/// while the resulting `mode: "insert"` is checked on the after-state).
public struct SuccessCriteria: Codable, Equatable, Sendable {

    // Event-level constraints (all must hold for one single event).

    /// `CommandEvent.Verb` name: move, delete, change, yank, put, putBefore,
    /// deleteChar, undo, enterInsert, leaveInsert, enterVisual, leaveVisual,
    /// write, quit, writeQuit.
    public var verb: String?
    /// `CommandEvent.Modifier` raw value: inside / around.
    public var modifier: String?
    /// `CommandEvent.Category` raw value: singleMotion, operatorMotion,
    /// fullGrammar, action, mode, commandLine.
    public var category: String?
    /// Motion name for `.motion` targets (wordForward, lineEnd, find, …).
    public var targetMotion: String?
    /// Required target character for find/till motions (single character).
    public var targetChar: String?
    /// `TextObjectKind` raw value for `.textObject` targets: word, quotedString,
    /// parens, paragraph.
    public var targetTextObject: String?
    /// Require a `.line` (linewise doubled) target.
    public var targetLine: Bool?
    /// Require a `.selection` (visual operand) target.
    public var targetSelection: Bool?
    /// Minimum count carried by the event (counts drills).
    public var minCount: Int?

    // State constraints, evaluated on the after-state (and before↔after deltas).

    /// `Mode` raw value the engine must be in afterwards.
    public var mode: String?
    /// Substrings the resulting buffer must contain.
    public var bufferContains: [String]?
    /// Substrings the resulting buffer must NOT contain.
    public var bufferOmits: [String]?
    /// Buffer text must be identical to the before-state (yanks, motions).
    public var bufferUnchanged: Bool?
    /// Buffer text must differ from the before-state (edits).
    public var bufferChanged: Bool?
    public var cursorLine: Int?
    public var cursorCol: Int?
    /// The character the cursor must land on.
    public var charUnderCursor: String?
    /// Substring the unnamed register must contain afterwards.
    public var registerContains: String?

    public init(
        verb: String? = nil,
        modifier: String? = nil,
        category: String? = nil,
        targetMotion: String? = nil,
        targetChar: String? = nil,
        targetTextObject: String? = nil,
        targetLine: Bool? = nil,
        targetSelection: Bool? = nil,
        minCount: Int? = nil,
        mode: String? = nil,
        bufferContains: [String]? = nil,
        bufferOmits: [String]? = nil,
        bufferUnchanged: Bool? = nil,
        bufferChanged: Bool? = nil,
        cursorLine: Int? = nil,
        cursorCol: Int? = nil,
        charUnderCursor: String? = nil,
        registerContains: String? = nil
    ) {
        self.verb = verb
        self.modifier = modifier
        self.category = category
        self.targetMotion = targetMotion
        self.targetChar = targetChar
        self.targetTextObject = targetTextObject
        self.targetLine = targetLine
        self.targetSelection = targetSelection
        self.minCount = minCount
        self.mode = mode
        self.bufferContains = bufferContains
        self.bufferOmits = bufferOmits
        self.bufferUnchanged = bufferUnchanged
        self.bufferChanged = bufferChanged
        self.cursorLine = cursorLine
        self.cursorCol = cursorCol
        self.charUnderCursor = charUnderCursor
        self.registerContains = registerContains
    }

    /// True when this attempt counts as a correct rep.
    public func matches(
        events: [CommandEvent],
        before: LessonEngineState,
        after: LessonEngineState
    ) -> Bool {
        guard events.contains(where: matchesEvent) else { return false }
        return matchesState(before: before, after: after)
    }

    // MARK: Event half

    private func matchesEvent(_ event: CommandEvent) -> Bool {
        if let verb, EventNaming.name(of: event.verb) != verb { return false }
        if let modifier, event.modifier?.rawValue != modifier { return false }
        if let category, event.category.rawValue != category { return false }
        if let minCount, event.count < minCount { return false }

        if targetMotion != nil || targetChar != nil {
            guard case .motion(let motion)? = event.target else { return false }
            if let targetMotion, EventNaming.name(of: motion) != targetMotion { return false }
            if let targetChar {
                guard let expected = targetChar.first, targetChar.count == 1,
                      EventNaming.character(of: motion) == expected
                else { return false }
            }
        }
        if let targetTextObject {
            guard case .textObject(let kind)? = event.target, kind.rawValue == targetTextObject
            else { return false }
        }
        if targetLine == true {
            guard case .line? = event.target else { return false }
        }
        if targetSelection == true {
            guard case .selection? = event.target else { return false }
        }
        return true
    }

    // MARK: State half

    private func matchesState(before: LessonEngineState, after: LessonEngineState) -> Bool {
        if let mode, after.mode.rawValue != mode { return false }
        if let bufferContains, !bufferContains.allSatisfy({ after.text.contains($0) }) { return false }
        if let bufferOmits, bufferOmits.contains(where: { after.text.contains($0) }) { return false }
        if bufferUnchanged == true, before.text != after.text { return false }
        if bufferChanged == true, before.text == after.text { return false }
        if let cursorLine, after.cursor.line != cursorLine { return false }
        if let cursorCol, after.cursor.col != cursorCol { return false }
        if let charUnderCursor {
            guard let expected = charUnderCursor.first, charUnderCursor.count == 1,
                  after.charUnderCursor == expected
            else { return false }
        }
        if let registerContains {
            guard let register = after.registerText, register.contains(registerContains) else { return false }
        }
        return true
    }
}

// MARK: - Engine snapshot

/// The slice of engine state a lesson step can assert on. Decouples the tutorial
/// from `VimEngine`'s internals (and lets tests fabricate states directly).
public struct LessonEngineState: Equatable, Sendable {
    public var text: String
    public var cursor: Position
    public var mode: Mode
    public var charUnderCursor: Character?
    public var registerText: String?
    /// True when the engine is part-way through a command: an operator is
    /// pending, an `f`/`t` is waiting for its character, an `i`/`a` is waiting
    /// for its text object, a count is being typed, insert mode is open, or a
    /// `:` prompt is up. Distinguishes "still typing" from "that command
    /// fizzled" — a no-op emits zero events, exactly like a half-typed one.
    public var isMidCommand: Bool

    public init(
        text: String,
        cursor: Position,
        mode: Mode,
        charUnderCursor: Character? = nil,
        registerText: String? = nil,
        isMidCommand: Bool = false
    ) {
        self.text = text
        self.cursor = cursor
        self.mode = mode
        self.charUnderCursor = charUnderCursor
        self.registerText = registerText
        self.isMidCommand = isMidCommand
    }

    public init(engine: VimEngine) {
        self.init(
            text: engine.buffer.text,
            cursor: engine.cursor,
            mode: engine.mode,
            charUnderCursor: engine.buffer.char(at: engine.cursor),
            registerText: engine.register?.text,
            isMidCommand: engine.isMidCommand
        )
    }
}

extension VimEngine {
    /// See `LessonEngineState.isMidCommand`. Read-only view of engine state —
    /// the Engine module itself is untouched.
    var isMidCommand: Bool {
        if mode == .operatorPending || mode == .commandLine || mode == .insert { return true }
        return pending != PendingState()
    }
}

// MARK: - Naming (JSON strings ↔ engine enums)

/// Maps `CommandEvent`'s non-RawRepresentable enums to the strings lessons.json
/// uses. Kept here so adding an engine case surfaces as a compile error.
enum EventNaming {
    static func name(of verb: CommandEvent.Verb) -> String {
        switch verb {
        case .move: return "move"
        case .delete: return "delete"
        case .change: return "change"
        case .yank: return "yank"
        case .put: return "put"
        case .putBefore: return "putBefore"
        case .deleteChar: return "deleteChar"
        case .undo: return "undo"
        case .enterInsert: return "enterInsert"
        case .leaveInsert: return "leaveInsert"
        case .enterVisual: return "enterVisual"
        case .leaveVisual: return "leaveVisual"
        case .write: return "write"
        case .quit: return "quit"
        case .writeQuit: return "writeQuit"
        }
    }

    static func name(of motion: Motion) -> String {
        switch motion {
        case .left: return "left"
        case .down: return "down"
        case .up: return "up"
        case .right: return "right"
        case .wordForward: return "wordForward"
        case .wordBackward: return "wordBackward"
        case .wordEnd: return "wordEnd"
        case .lineStart: return "lineStart"
        case .lineEnd: return "lineEnd"
        case .firstNonBlank: return "firstNonBlank"
        case .fileStart: return "fileStart"
        case .fileEnd: return "fileEnd"
        case .find: return "find"
        case .till: return "till"
        case .findBack: return "findBack"
        case .tillBack: return "tillBack"
        case .repeatFind: return "repeatFind"
        case .repeatFindReverse: return "repeatFindReverse"
        }
    }

    static func character(of motion: Motion) -> Character? {
        switch motion {
        case .find(let c), .till(let c), .findBack(let c), .tillBack(let c): return c
        default: return nil
        }
    }
}
