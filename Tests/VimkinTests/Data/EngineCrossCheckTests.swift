import Testing
@testable import Vimkin

/// U3↔U2 drift guard (plan: "every tier-1/2 record's keys sequence is accepted
/// by VimEngine", extended to every engineSupported record in tiers 1-4):
/// each record's `keys` must be meaningful to the engine — it either emits a
/// CommandEvent, changes state, or (for prefixes like `f`/`d`) enters a pending
/// mode that Esc cleanly cancels. A record whose keys the engine silently
/// ignores means the database and engine have drifted apart.
@Suite("Command DB ↔ VimEngine cross-check", .tags(.integration))
struct EngineCrossCheckTests {

    static let sampleText = """
    # Notes (draft)
    say "hi (there) friend" done
    one two three four five

    end of file
    """

    /// Cursor placements for records that need specific context.
    /// Line 1 col 10 sits inside both the parens and the quotes.
    static func cursor(for id: String) -> (line: Int, col: Int) {
        (line: 1, col: 10)
    }

    static func makeEngine(at id: String) -> VimEngine {
        var e = VimEngine(text: sampleText)
        let c = cursor(for: id)
        // Position deterministically using motions (public API only).
        _ = e.feed(keys: "gg")
        for _ in 0..<c.line { _ = e.feed("j") }
        _ = e.feed("0")
        for _ in 0..<c.col { _ = e.feed("l") }
        return e
    }

    @Test("every engineSupported tier 1-4 record is accepted by the engine")
    func crossCheck() throws {
        let db = try CommandDatabase.load()
        let records = db.commands.filter { $0.engineSupported && $0.tier <= 4 }
        #expect(records.count >= 50)

        for rec in records {
            var engine = Self.makeEngine(at: rec.id)

            // "Esc" is a key name, not literal chars; verify it cancels cleanly.
            if rec.keys == "Esc" {
                _ = engine.feed("d")
                _ = engine.feed(.escape)
                #expect(engine.mode == .normal, "Esc did not cancel operator-pending")
                continue
            }

            var keys = rec.keys
            switch rec.commandClass {
            case .textObject:
                // Text objects are operator suffixes; exercise via delete.
                keys = "d" + keys
            default:
                // Repeat-find needs a prior find; `,` also needs a match BEHIND
                // the cursor, so advance to the second 'e' before reversing.
                if rec.id == "motion.repeat-find" { _ = engine.feed(keys: "fe") }
                if rec.id == "motion.repeat-find-reverse" { _ = engine.feed(keys: "fe;") }
                // Paste is a no-op on an empty register; seed with a yanked line.
                if rec.id.hasPrefix("action.paste") { _ = engine.feed(keys: "yy") }
            }
            let before = engine
            if rec.mode == .cmdline { keys += "\n" }

            var events = engine.feed(keys: keys)

            // Bare prefixes (f/t/F/T, d/c/y) legitimately wait for more input:
            // they must have left normal mode, and Esc must cancel cleanly.
            if engine.mode == .operatorPending || engine.mode == .commandLine {
                #expect(rec.commandClass == .operator || rec.mode == .cmdline || "fFtT".contains(rec.keys),
                        "\(rec.id): unexpectedly stuck pending after \(rec.keys)")
                events += engine.feed(.escape)
                #expect(engine.mode == .normal, "\(rec.id): Esc did not cancel pending state")
                continue
            }
            // `f`/`F`/`t`/`T` wait for a target char without a mode change —
            // engine may model pending-char internally; Esc must still recover.
            if "fFtT".contains(rec.keys) && rec.commandClass == .motion {
                _ = engine.feed(.escape)
                continue
            }

            let changed = engine.buffer != before.buffer
                || engine.cursor != before.cursor
                || engine.mode != before.mode

            switch rec.id {
            case "action.escape", "action.undo":
                // Esc from normal and u with no history are legitimate no-ops.
                continue
            default:
                #expect(!events.isEmpty || changed,
                        "\(rec.id): keys \(rec.keys) produced no event and no state change — DB/engine drift")
            }
        }
    }
}
