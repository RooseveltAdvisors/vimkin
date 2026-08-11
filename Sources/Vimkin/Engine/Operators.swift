// Operators.swift — d/c/y application over motions, linewise doubles, text objects,
// x/p/P, and visual-mode operators. Register + undo semantics live here.

enum Operators {

    // MARK: - Operator + motion

    static func applyOperator(
        engine: inout VimEngine, op: VimEngine.Operator, motion: Motion, count: Int,
        resolver: MotionResolver
    ) -> [CommandEvent] {
        engine.resetPending()
        engine.setMode(.normal)

        let cursor = engine.cursor
        let buffer = engine.buffer

        // The w motion has operator-specific special cases (:h word-motions, :h cw).
        if motion == .wordForward {
            let end: Position
            if op == .change, buffer.char(at: cursor).map(CharClass.init) ?? .whitespace != .whitespace {
                // cw on a non-blank behaves like ce: change through end of word.
                var e = cursor
                for _ in 0 ..< max(1, count) { e = resolver.wordEnd(from: e) }
                end = Position(line: e.line, col: e.col + 1)  // inclusive
            } else {
                // dw/yw (and cw on whitespace): exclusive, clamped at end of line
                // when the last word moved over ends the line.
                end = resolver.wordForwardOperatorEnd(from: cursor, count: max(1, count))
            }
            return applyCharwise(
                engine: &engine, op: op, start: cursor, endExclusive: end,
                event: operatorEvent(op, target: .motion(motion), count: count, category: .operatorMotion)
            )
        }

        guard let result = resolver.resolve(
            motion, from: cursor, count: count, lastFind: engine.lastFind, desiredCol: cursor.col
        ) else {
            return []  // failed motion (f with no match): operator aborts, nothing changes
        }
        engine.setLastFind(result.newLastFind)

        let event = operatorEvent(op, target: .motion(motion), count: count, category: .operatorMotion)

        switch result.span {
        case .linewise:
            let lo = min(cursor.line, result.target.line)
            let hi = max(cursor.line, result.target.line)
            return applyLinewiseRange(engine: &engine, op: op, lines: lo ... hi, event: event)
        case .charwiseExclusive:
            let start = min(cursor, result.target)
            let end = max(cursor, result.target)
            return applyCharwise(engine: &engine, op: op, start: start, endExclusive: end, event: event)
        case .charwiseInclusive:
            let start = min(cursor, result.target)
            let endBase = max(cursor, result.target)
            let end = Position(line: endBase.line, col: endBase.col + 1)
            return applyCharwise(engine: &engine, op: op, start: start, endExclusive: end, event: event)
        }
    }

    // MARK: - Linewise doubles (dd cc yy)

    static func applyLinewise(engine: inout VimEngine, op: VimEngine.Operator) -> [CommandEvent] {
        let count = max(1, engine.pending.rawCount)
        engine.resetPending()
        engine.setMode(.normal)
        let start = engine.cursor.line
        let end = min(engine.buffer.lineCount - 1, start + count - 1)
        let event = operatorEvent(op, target: .line, count: count, category: .operatorMotion)
        return applyLinewiseRange(engine: &engine, op: op, lines: start ... end, event: event)
    }

    // MARK: - Shared application

    private static func applyCharwise(
        engine: inout VimEngine, op: VimEngine.Operator,
        start: Position, endExclusive: Position, event: CommandEvent
    ) -> [CommandEvent] {
        var buffer = engine.buffer

        switch op {
        case .yank:
            var scratch = buffer
            let text = scratch.deleteCharRange(from: start, toExclusive: endExclusive)
            engine.setRegister(.charwise(text))
            // vim: cursor moves to the start of the yanked region.
            var c = start
            c.col = buffer.clampColForNormal(c.col, line: c.line)
            engine.setCursor(c)
            return [event]
        case .delete:
            engine.pushUndoSnapshot()
            let text = buffer.deleteCharRange(from: start, toExclusive: endExclusive)
            engine.setBuffer(buffer)
            engine.setRegister(.charwise(text))
            var c = start
            c.col = buffer.clampColForNormal(c.col, line: c.line)
            engine.setCursor(c)
            return [event]
        case .change:
            engine.pushUndoSnapshot()
            let text = buffer.deleteCharRange(from: start, toExclusive: endExclusive)
            engine.setBuffer(buffer)
            engine.setRegister(.charwise(text))
            var c = start
            c.col = buffer.clampColForInsert(c.col, line: c.line)
            engine.setCursor(c)
            engine.setMode(.insert)
            var events = [event]
            events.append(CommandEvent(verb: .enterInsert, category: .mode))
            return events
        }
    }

    private static func applyLinewiseRange(
        engine: inout VimEngine, op: VimEngine.Operator,
        lines: ClosedRange<Int>, event: CommandEvent
    ) -> [CommandEvent] {
        var buffer = engine.buffer

        switch op {
        case .yank:
            engine.setRegister(.linewise(Array(buffer.lines[lines])))
            return [event]
        case .delete:
            engine.pushUndoSnapshot()
            let removed = buffer.deleteLines(lines)
            engine.setBuffer(buffer)
            engine.setRegister(.linewise(removed))
            let line = min(lines.lowerBound, buffer.lineCount - 1)
            engine.setCursor(Position(line: line, col: buffer.firstNonBlankCol(line)))
            return [event]
        case .change:
            engine.pushUndoSnapshot()
            engine.setRegister(.linewise(Array(buffer.lines[lines])))
            buffer.deleteLines(lines)
            // cc replaces the lines with one empty line and enters insert there.
            let insertAt = min(lines.lowerBound, buffer.lineCount)
            if buffer.lines == [""] && buffer.lineCount == 1 && lines.lowerBound == 0 {
                // deleting everything already left the canonical empty buffer
            } else {
                buffer.insertLines([""], at: insertAt)
            }
            engine.setBuffer(buffer)
            engine.setCursor(Position(line: min(insertAt, buffer.lineCount - 1), col: 0))
            engine.setMode(.insert)
            var events = [event]
            events.append(CommandEvent(verb: .enterInsert, category: .mode))
            return events
        }
    }

    private static func operatorEvent(
        _ op: VimEngine.Operator, modifier: CommandEvent.Modifier? = nil,
        target: CommandEvent.Target, count: Int, category: CommandEvent.Category
    ) -> CommandEvent {
        let verb: CommandEvent.Verb
        switch op {
        case .delete: verb = .delete
        case .change: verb = .change
        case .yank: verb = .yank
        }
        return CommandEvent(
            verb: verb, modifier: modifier, target: target,
            count: max(1, count), category: category
        )
    }

    // MARK: - Text objects (iw aw i" a" i( a( ip ap)

    static func applyTextObject(
        engine: inout VimEngine, modifier: CommandEvent.Modifier, objectKey: Character
    ) -> [CommandEvent] {
        let op = engine.pending.op
        let count = engine.pending.rawCount
        engine.resetPending()
        engine.setMode(.normal)
        guard let op else {
            // Text objects in visual mode are out of the v1 surface.
            engine.clearVisual()
            return []
        }
        let resolver = TextObjectResolver(buffer: engine.buffer)
        guard let (range, kind) = resolver.resolve(key: objectKey, modifier: modifier, at: engine.cursor) else {
            return []
        }
        let event = operatorEvent(
            op, modifier: modifier, target: .textObject(kind), count: count, category: .fullGrammar
        )
        switch range {
        case .charwise(let start, let endExclusive):
            return applyCharwise(engine: &engine, op: op, start: start, endExclusive: endExclusive, event: event)
        case .linewise(let lineRange):
            return applyLinewiseRange(engine: &engine, op: op, lines: lineRange, event: event)
        }
    }

    // MARK: - x

    static func deleteChar(engine: inout VimEngine) -> [CommandEvent] {
        let count = max(1, engine.pending.rawCount)
        engine.resetPending()
        let buffer = engine.buffer
        let cursor = engine.cursor
        let len = buffer.lineLength(cursor.line)
        guard len > 0, cursor.col < len else { return [] }
        engine.pushUndoSnapshot()
        var b = buffer
        let end = Position(line: cursor.line, col: min(len, cursor.col + count))
        let text = b.deleteCharRange(from: cursor, toExclusive: end)
        engine.setBuffer(b)
        engine.setRegister(.charwise(text))
        var c = cursor
        c.col = b.clampColForNormal(c.col, line: c.line)
        engine.setCursor(c)
        return [CommandEvent(verb: .deleteChar, count: count, category: .action)]
    }

    // MARK: - p / P

    static func put(engine: inout VimEngine, after: Bool) -> [CommandEvent] {
        let count = max(1, engine.pending.rawCount)
        engine.resetPending()
        guard let register = engine.register else { return [] }

        let verb: CommandEvent.Verb = after ? .put : .putBefore
        var buffer = engine.buffer
        let cursor = engine.cursor

        switch register.kind {
        case .charwise:
            guard !register.text.isEmpty else { return [] }
            engine.pushUndoSnapshot()
            let text = String(repeating: register.text, count: count)
            let len = buffer.lineLength(cursor.line)
            let insertCol = after ? min(len, cursor.col + (len == 0 ? 0 : 1)) : cursor.col
            let insertAt = Position(line: cursor.line, col: insertCol)
            let end = buffer.insert(text, at: insertAt)
            engine.setBuffer(buffer)
            // Cursor lands on the last character of the pasted text.
            var c = end
            if c.col > 0 {
                c.col -= 1
            } else if c.line > 0 {
                c.line -= 1
                c.col = max(0, buffer.lineLength(c.line) - 1)
            }
            c.col = buffer.clampColForNormal(c.col, line: c.line)
            engine.setCursor(c)
            return [CommandEvent(verb: verb, count: count, category: .action)]
        case .linewise:
            guard !register.lines.isEmpty else { return [] }
            engine.pushUndoSnapshot()
            var newLines: [String] = []
            for _ in 0 ..< count { newLines.append(contentsOf: register.lines) }
            let index = after ? cursor.line + 1 : cursor.line
            buffer.insertLines(newLines, at: index)
            engine.setBuffer(buffer)
            engine.setCursor(Position(line: index, col: buffer.firstNonBlankCol(index)))
            return [CommandEvent(verb: verb, count: count, category: .action)]
        }
    }

    // MARK: - Visual-mode operators

    static func applyVisual(engine: inout VimEngine, op: VimEngine.Operator) -> [CommandEvent] {
        engine.resetPending()
        let anchor = engine.visualAnchor ?? engine.cursor
        engine.setMode(.normal)
        engine.clearVisual()

        // Charwise visual selection is inclusive of both ends.
        let start = min(anchor, engine.cursor)
        let endBase = max(anchor, engine.cursor)
        let endExclusive = Position(line: endBase.line, col: endBase.col + 1)
        let event = operatorEvent(op, target: .selection, count: 1, category: .operatorMotion)
        return applyCharwise(engine: &engine, op: op, start: start, endExclusive: endExclusive, event: event)
    }

    /// x in visual mode deletes the selection (like d).
    static func deleteVisualSelection(engine: inout VimEngine) -> [CommandEvent] {
        applyVisual(engine: &engine, op: .delete)
    }
}
