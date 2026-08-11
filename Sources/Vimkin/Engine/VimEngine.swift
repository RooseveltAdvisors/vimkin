// VimEngine.swift — the deterministic modal-editing state machine.
// Pure Swift, no UI imports. API: feed(_:) -> [CommandEvent] + readable state.
//
// v1 command surface (curriculum tiers 1-2, per plan U2 / KTD 3):
//   modes:    normal, insert (i a o I A O, Esc), operator-pending, visual charwise (v),
//             minimal command line (:w :q :wq)
//   motions:  h j k l, w b e, 0 $ ^, gg G, f t F T ; ,
//   operators: d c y (+ motions and text objects), dd cc yy, x, p, P, u; counts compose
//   text objects: iw aw i" a" i( a( ip ap
//   register: single unnamed register with charwise/linewise kind
//   undo:     snapshot stack (buffer + cursor), u restores

public struct VimEngine: Equatable, Sendable {
    public private(set) var buffer: TextBuffer
    public private(set) var cursor: Position
    public private(set) var mode: Mode
    /// Contents of the `:` prompt while in commandLine mode (excluding the colon).
    public private(set) var commandLine: String = ""
    /// The single unnamed register.
    public private(set) var register: Register?

    var lastFind: FindState?
    var desiredCol: Int = 0
    var pending = PendingState()
    var undoStack: [Snapshot] = []
    /// Visual-mode anchor (selection runs anchor...cursor inclusive, either order).
    var visualAnchor: Position?

    struct Snapshot: Equatable, Sendable {
        var buffer: TextBuffer
        var cursor: Position
    }

    enum Operator: Character, Equatable, Sendable {
        case delete = "d"
        case change = "c"
        case yank = "y"
    }

    struct PendingState: Equatable, Sendable {
        var count: Int?              // count typed before an operator (or bare count)
        var op: Operator?            // pending d / c / y
        var opCount: Int?            // count typed after the operator
        var awaitingFindChar: Motion.FindKind?
        var awaitingObjectChar: CommandEvent.Modifier?  // i or a typed, waiting for object key
        var sawG: Bool = false

        mutating func reset() { self = PendingState() }

        var isCountInProgress: Bool {
            (op == nil && count != nil) || (op != nil && opCount != nil)
        }

        /// 0 when no explicit count was typed; otherwise the composed product (3d2w = 6).
        var rawCount: Int {
            if count == nil && opCount == nil { return 0 }
            return (count ?? 1) * (opCount ?? 1)
        }
    }

    // MARK: - Init

    public init(text: String) {
        self.buffer = TextBuffer(text: text)
        self.cursor = Position(line: 0, col: 0)
        self.mode = .normal
    }

    // MARK: - Input

    @discardableResult
    public mutating func feed(_ key: KeyInput) -> [CommandEvent] {
        switch mode {
        case .insert:
            return handleInsert(key)
        case .commandLine:
            return handleCommandLine(key)
        case .normal, .visual, .operatorPending:
            return handleNormalFamily(key)
        }
    }

    /// Convenience: feed a string of keys. "\u{1B}" maps to Esc, "\n"/"\r" to Enter.
    @discardableResult
    public mutating func feed(keys: String) -> [CommandEvent] {
        var events: [CommandEvent] = []
        for c in keys {
            switch c {
            case "\u{1B}": events += feed(.escape)
            case "\n", "\r": events += feed(.enter)
            default: events += feed(.char(c))
            }
        }
        return events
    }

    // MARK: - Insert mode

    private mutating func handleInsert(_ key: KeyInput) -> [CommandEvent] {
        switch key {
        case .char(let c):
            buffer.insert(String(c), at: cursor)
            cursor.col += 1
            return []
        case .enter:
            buffer.splitLine(at: cursor)
            cursor = Position(line: cursor.line + 1, col: 0)
            return []
        case .escape:
            mode = .normal
            cursor.col = buffer.clampColForNormal(cursor.col - 1, line: cursor.line)
            desiredCol = cursor.col
            return [CommandEvent(verb: .leaveInsert, category: .mode)]
        }
    }

    // MARK: - Command-line mode

    private mutating func handleCommandLine(_ key: KeyInput) -> [CommandEvent] {
        switch key {
        case .char(let c):
            commandLine.append(c)
            return []
        case .escape:
            commandLine = ""
            mode = .normal
            return []
        case .enter:
            let cmd = commandLine
            commandLine = ""
            mode = .normal
            switch cmd {
            case "w": return [CommandEvent(verb: .write, category: .commandLine)]
            case "q": return [CommandEvent(verb: .quit, category: .commandLine)]
            case "wq": return [CommandEvent(verb: .writeQuit, category: .commandLine)]
            default: return []  // anything else no-ops (v1 scope)
            }
        }
    }

    // MARK: - Normal / visual / operator-pending dispatch

    private mutating func handleNormalFamily(_ key: KeyInput) -> [CommandEvent] {
        switch key {
        case .escape:
            pending.reset()
            if mode == .visual {
                mode = .normal
                visualAnchor = nil
                return [CommandEvent(verb: .leaveVisual, category: .mode)]
            }
            if mode == .operatorPending {
                mode = .normal
            }
            return []
        case .enter:
            pending.reset()
            return []
        case .char(let c):
            return handleNormalChar(c)
        }
    }

    private mutating func handleNormalChar(_ c: Character) -> [CommandEvent] {
        // 1. A pending f/t/F/T is waiting for its target character.
        if let kind = pending.awaitingFindChar {
            pending.awaitingFindChar = nil
            return executeMotion(kind.motion(c))
        }

        // 2. A pending i/a (after an operator or in visual mode) is waiting for an object key.
        if let modifier = pending.awaitingObjectChar {
            pending.awaitingObjectChar = nil
            return executeTextObject(modifier: modifier, objectKey: c)
        }

        // 3. Counts. "0" is a motion when no count is in progress.
        if let digit = c.wholeNumberValue, c.isASCII, c.isNumber {
            if c == "0" && !pending.isCountInProgress {
                return executeMotion(.lineStart)
            }
            if pending.op == nil {
                pending.count = (pending.count ?? 0) * 10 + digit
            } else {
                pending.opCount = (pending.opCount ?? 0) * 10 + digit
            }
            return []
        }

        // 4. g-prefix (gg).
        if pending.sawG {
            pending.sawG = false
            if c == "g" {
                return executeMotion(.fileStart)
            }
            pending.reset()
            if mode == .operatorPending { mode = .normal }
            return []
        }
        if c == "g" {
            pending.sawG = true
            return []
        }

        // 5. Operators and doubled linewise forms (dd cc yy).
        if let op = Operator(rawValue: c) {
            if mode == .visual {
                return applyVisualOperator(op)
            }
            if let pendingOp = pending.op {
                if pendingOp == op {
                    return executeLinewiseOperator(op)
                }
                // Mismatched operator (e.g. d then y) aborts in vim.
                pending.reset()
                mode = .normal
                return []
            }
            pending.op = op
            mode = .operatorPending
            return []
        }

        // 6. Text-object modifiers / insert entries. In operator-pending or visual mode,
        //    i/a begin a text object; in normal mode they enter insert.
        if c == "i" || c == "a" {
            if pending.op != nil || mode == .visual {
                pending.awaitingObjectChar = c == "i" ? .inside : .around
                return []
            }
            return enterInsert(c)
        }

        // 7. Motions.
        if let motion = Self.simpleMotion(for: c) {
            return executeMotion(motion)
        }
        switch c {
        case "f": pending.awaitingFindChar = .find; return []
        case "t": pending.awaitingFindChar = .till; return []
        case "F": pending.awaitingFindChar = .findBack; return []
        case "T": pending.awaitingFindChar = .tillBack; return []
        default: break
        }

        // 8. Normal-mode-only commands (insert entries, actions, mode switches).
        if mode == .operatorPending {
            // Any other key cancels the operator (vim aborts on invalid motion).
            pending.reset()
            mode = .normal
            return []
        }

        switch c {
        case "o", "I", "A", "O":
            if mode == .visual { pending.reset(); return [] }
            return enterInsert(c)
        case "x":
            if mode == .visual { return Operators.deleteVisualSelection(engine: &self) }
            return deleteCharUnderCursor()
        case "p":
            if mode == .visual { pending.reset(); return [] }  // visual paste: out of v1 scope
            return put(after: true)
        case "P":
            if mode == .visual { pending.reset(); return [] }
            return put(after: false)
        case "u":
            if mode == .visual { pending.reset(); return [] }
            return undo()
        case "v":
            return toggleVisual()
        case ":":
            if mode == .visual { pending.reset(); return [] }
            mode = .commandLine
            commandLine = ""
            pending.reset()
            return []
        default:
            pending.reset()
            return []
        }
    }

    static func simpleMotion(for c: Character) -> Motion? {
        switch c {
        case "h": return .left
        case "j": return .down
        case "k": return .up
        case "l": return .right
        case "w": return .wordForward
        case "b": return .wordBackward
        case "e": return .wordEnd
        case "$": return .lineEnd
        case "^": return .firstNonBlank
        case "G": return .fileEnd
        case ";": return .repeatFind
        case ",": return .repeatFindReverse
        default: return nil
        }
    }

    // MARK: - Motion execution

    private mutating func executeMotion(_ motion: Motion) -> [CommandEvent] {
        let count = pending.rawCount
        let resolver = MotionResolver(buffer: buffer)

        if let op = pending.op {
            return applyOperator(op, motion: motion, count: count, resolver: resolver)
        }

        guard let result = resolver.resolve(
            motion, from: cursor, count: count, lastFind: lastFind, desiredCol: effectiveDesiredCol
        ) else {
            pending.reset()
            return []
        }

        var target = result.target
        if mode != .insert {
            target.col = buffer.clampColForNormal(target.col, line: target.line)
        }
        cursor = target
        lastFind = result.newLastFind
        desiredCol = result.desiredCol ?? target.col
        pending.reset()
        return [CommandEvent(
            verb: .move,
            target: .motion(motion),
            count: max(1, count),
            category: .singleMotion
        )]
    }

    private var effectiveDesiredCol: Int {
        max(desiredCol, cursor.col)
    }

    // MARK: - Insert entries

    private mutating func enterInsert(_ c: Character) -> [CommandEvent] {
        pushUndoSnapshot()
        pending.reset()
        switch c {
        case "i":
            break
        case "a":
            cursor.col = buffer.clampColForInsert(cursor.col + 1, line: cursor.line)
            if buffer.lineLength(cursor.line) == 0 { cursor.col = 0 }
        case "I":
            cursor.col = buffer.firstNonBlankCol(cursor.line)
        case "A":
            cursor.col = buffer.lineLength(cursor.line)
        case "o":
            buffer.insertLines([""], at: cursor.line + 1)
            cursor = Position(line: cursor.line + 1, col: 0)
        case "O":
            buffer.insertLines([""], at: cursor.line)
            cursor = Position(line: cursor.line, col: 0)
        default:
            break
        }
        mode = .insert
        return [CommandEvent(verb: .enterInsert, category: .mode)]
    }

    // MARK: - Undo

    mutating func pushUndoSnapshot() {
        undoStack.append(Snapshot(buffer: buffer, cursor: cursor))
    }

    private mutating func undo() -> [CommandEvent] {
        pending.reset()
        guard let snapshot = undoStack.popLast() else { return [] }
        buffer = snapshot.buffer
        cursor = snapshot.cursor
        cursor.col = buffer.clampColForNormal(cursor.col, line: min(cursor.line, buffer.lineCount - 1))
        cursor.line = min(cursor.line, buffer.lineCount - 1)
        desiredCol = cursor.col
        return [CommandEvent(verb: .undo, category: .action)]
    }

    // MARK: - Stubs filled in by later families (operators, registers, visual)

    private mutating func applyOperator(
        _ op: Operator, motion: Motion, count: Int, resolver: MotionResolver
    ) -> [CommandEvent] {
        Operators.applyOperator(engine: &self, op: op, motion: motion, count: count, resolver: resolver)
    }

    private mutating func executeLinewiseOperator(_ op: Operator) -> [CommandEvent] {
        Operators.applyLinewise(engine: &self, op: op)
    }

    private mutating func executeTextObject(
        modifier: CommandEvent.Modifier, objectKey: Character
    ) -> [CommandEvent] {
        Operators.applyTextObject(engine: &self, modifier: modifier, objectKey: objectKey)
    }

    private mutating func deleteCharUnderCursor() -> [CommandEvent] {
        Operators.deleteChar(engine: &self)
    }

    private mutating func put(after: Bool) -> [CommandEvent] {
        Operators.put(engine: &self, after: after)
    }

    private mutating func toggleVisual() -> [CommandEvent] {
        pending.reset()
        if mode == .visual {
            mode = .normal
            visualAnchor = nil
            return [CommandEvent(verb: .leaveVisual, category: .mode)]
        }
        mode = .visual
        visualAnchor = cursor
        return [CommandEvent(verb: .enterVisual, category: .mode)]
    }

    private mutating func applyVisualOperator(_ op: Operator) -> [CommandEvent] {
        Operators.applyVisual(engine: &self, op: op)
    }

    // MARK: - Internal accessors for Operators (same-module surgery)

    mutating func setBuffer(_ b: TextBuffer) { buffer = b }
    mutating func setCursor(_ p: Position) { cursor = p; desiredCol = p.col }
    mutating func setMode(_ m: Mode) { mode = m }
    mutating func setRegister(_ r: Register) { register = r }
    mutating func setLastFind(_ f: FindState?) { lastFind = f }
    mutating func clearVisual() { visualAnchor = nil }
    mutating func resetPending() { pending.reset() }
}

extension Motion {
    /// The four find kinds, used while waiting for the target character.
    enum FindKind: Equatable, Sendable {
        case find, till, findBack, tillBack

        func motion(_ c: Character) -> Motion {
            switch self {
            case .find: return .find(c)
            case .till: return .till(c)
            case .findBack: return .findBack(c)
            case .tillBack: return .tillBack(c)
            }
        }
    }
}
