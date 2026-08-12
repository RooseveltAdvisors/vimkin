// DrillSiteFinder.swift — turns a drillable command + a real corpus document
// into concrete, SOLVABLE drill sites.
//
// The load-bearing idea: a drill's success rule is not hand-written, it is
// SIMULATED. We place a real VimEngine at a candidate cursor position, feed the
// target command's canonical keys, and record the end state as the goal. A
// generated drill therefore cannot be impossible — the goal is, by
// construction, a state the target command actually produces. (The solvability
// test replays this independently and proves it.)
//
// The same simulation runs for each confusable command, giving each site a
// precomputed near-miss table.

import Foundation

/// One concrete place in one document where a command can be drilled.
struct DrillSite: Sendable {
    let start: Position
    let solutionKeys: String
    let instruction: String
    let goal: DrillGoal
    let nearMisses: [NearMissCandidate]
}

/// Shared engine helpers for placing and snapshotting drill state.
enum DrillEngineSupport {
    /// Keys that move a fresh engine's cursor to `position` deterministically:
    /// jump to the line, snap to column 0, then step right.
    /// (`{n}G` → line, `0` → line start, `{n}l` → column.)
    static func positioningKeys(to position: Position) -> String {
        var keys = "\(position.line + 1)G0"
        if position.col > 0 { keys += "\(position.col)l" }
        return keys
    }

    /// A fresh engine parked at `position`, or nil when the position is not
    /// reachable (column past the end of a short line).
    static func engine(text: String, at position: Position) -> VimEngine? {
        var engine = VimEngine(text: text)
        engine.feed(keys: positioningKeys(to: position))
        guard engine.cursor == position, engine.mode == .normal else { return nil }
        return engine
    }

    /// The most specific category among a batch of events. `ci"` emits both a
    /// `.fullGrammar` change and a `.mode` enterInsert; the grammar one is what
    /// identifies the command.
    static func dominantCategory(_ events: [CommandEvent]) -> CommandEvent.Category? {
        events.map(\.category).max { rank($0) < rank($1) }
    }

    private static func rank(_ category: CommandEvent.Category) -> Int {
        switch category {
        case .fullGrammar: return 5
        case .operatorMotion: return 4
        case .action: return 3
        case .commandLine: return 2
        case .singleMotion: return 1
        case .mode: return 0
        }
    }

    /// Whether a register actually captured something.
    static func registerHasContent(_ register: Register?) -> Bool {
        guard let register else { return false }
        switch register.kind {
        case .charwise: return !register.text.isEmpty
        case .linewise: return !register.lines.isEmpty
        }
    }

    /// Human-readable form of captured text, for instruction phrasing.
    static func capturedText(_ register: Register?) -> String {
        guard let register else { return "" }
        let raw = register.kind == .linewise
            ? register.lines.joined(separator: " ")
            : register.text
        let collapsed = raw
            .split(whereSeparator: { $0 == "\n" || $0 == "\t" || $0 == " " })
            .joined(separator: " ")
        guard collapsed.count > 30 else { return collapsed }
        return String(collapsed.prefix(29)) + "…"
    }
}

enum DrillSiteFinder {
    /// Max candidate columns examined per line (bounds generation cost).
    private static let columnsPerLine = 6

    /// Every viable site for `template` in `document`, capped at `limit`.
    static func sites(
        for template: DrillTemplate,
        in document: CorpusDocument,
        limit: Int = 6
    ) -> [DrillSite] {
        let lines = TextBuffer(text: document.contents).lines
        var found: [DrillSite] = []

        for lineIndex in scanOrder(lineCount: lines.count, salt: template.commandID) {
            let line = lines[lineIndex]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            for col in candidateColumns(in: line) {
                let start = Position(line: lineIndex, col: col)
                if let site = site(for: template, in: document, at: start, lines: lines) {
                    found.append(site)
                    if found.count >= limit { return found }
                }
            }
        }
        return found
    }

    /// Line visiting order: a strided walk so a command's sites are spread
    /// across the whole document instead of clustering in its opening lines.
    /// Deterministic (salted by command id), and it visits every line exactly
    /// once because the stride is coprime with the line count by construction.
    private static func scanOrder(lineCount: Int, salt: String) -> [Int] {
        guard lineCount > 1 else { return lineCount == 1 ? [0] : [] }
        var stride = 7
        while stride > 1 && greatestCommonDivisor(stride, lineCount) != 1 { stride -= 1 }
        let start = Int(stableHash(salt) % UInt64(lineCount))
        return (0..<lineCount).map { (start + $0 * stride) % lineCount }
    }

    /// FNV-1a — a stable hash. (`String.hashValue` is seeded per process, so it
    /// would break seed reproducibility across launches.)
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : greatestCommonDivisor(b, a % b)
    }

    /// Interesting cursor columns on a line: line start, first text, each word
    /// start, one mid-word position, and the last character.
    private static func candidateColumns(in line: String) -> [Int] {
        let chars = Array(line)
        guard !chars.isEmpty else { return [] }

        var columns: [Int] = [0]
        if let firstText = chars.firstIndex(where: { $0 != " " && $0 != "\t" }) {
            columns.append(firstText)
        }
        var wordStarts: [Int] = []
        for (i, c) in chars.enumerated() where c != " " && c != "\t" {
            if i == 0 || chars[i - 1] == " " || chars[i - 1] == "\t" { wordStarts.append(i) }
        }
        columns.append(contentsOf: wordStarts)
        // One mid-word column so text objects are exercised from inside a word.
        if let second = wordStarts.dropFirst().first, second + 1 < chars.count {
            columns.append(second + 1)
        }
        columns.append(chars.count - 1)

        var seen = Set<Int>()
        return columns
            .filter { $0 >= 0 && $0 < chars.count && seen.insert($0).inserted }
            .sorted()
            .prefix(columnsPerLine)
            .map { $0 }
    }

    /// Builds a site at one candidate position, or nil when the command would
    /// be a no-op / degenerate there.
    private static func site(
        for template: DrillTemplate,
        in document: CorpusDocument,
        at start: Position,
        lines: [String]
    ) -> DrillSite? {
        guard let argument = resolveArgument(template.argument, at: start, lines: lines) else {
            return nil
        }
        let keys = substitute(template.keys, char: argument)

        guard let outcome = simulate(text: document.contents, at: start, keys: keys) else {
            return nil
        }
        guard satisfies(template.requirement, before: outcome.before, after: outcome.after) else {
            return nil
        }

        let capturesRegister = template.requirement == .registerNotEmpty
        let goal = DrillGoal.describing(
            outcome.after,
            category: outcome.category,
            includeRegister: capturesRegister
        )

        let word = DrillEngineSupport.capturedText(outcome.after.register)
        if template.phrase.contains("{word}"),
           !word.contains(where: { $0.isLetter || $0.isNumber }) {
            // A drill that says "delete the word `{`" is technically true and
            // pedagogically useless — hold out for real words.
            return nil
        }

        let nearMisses = template.confusables.compactMap { confusable -> NearMissCandidate? in
            let missKeys = substitute(confusable.keys, char: argument)
            guard missKeys != keys,
                  let missOutcome = simulate(text: document.contents, at: start, keys: missKeys)
            else { return nil }
            let missGoal = DrillGoal.describing(
                missOutcome.after,
                category: missOutcome.category,
                includeRegister: capturesRegister
            )
            // Indistinguishable from the correct answer ⇒ not a near miss.
            guard missGoal != goal else { return nil }
            return NearMissCandidate(
                performedKeys: missKeys,
                outcome: missGoal,
                feedback: "Close — `\(missKeys)` \(confusable.note); "
                    + "`\(keys)` \(template.note)."
            )
        }

        return DrillSite(
            start: start,
            solutionKeys: keys,
            instruction: instruction(
                for: template, word: word, char: argument, line: start.line
            ),
            goal: goal,
            nearMisses: nearMisses
        )
    }

    // MARK: - Simulation

    private struct Simulation {
        let before: DrillState
        let after: DrillState
        let category: CommandEvent.Category?
    }

    private static func simulate(text: String, at start: Position, keys: String) -> Simulation? {
        guard var engine = DrillEngineSupport.engine(text: text, at: start) else { return nil }
        let before = DrillState(engine: engine)
        let events = engine.feed(keys: keys)
        guard !events.isEmpty else { return nil }
        return Simulation(
            before: before,
            after: DrillState(engine: engine),
            category: DrillEngineSupport.dominantCategory(events)
        )
    }

    private static func satisfies(
        _ requirement: DrillRequirement, before: DrillState, after: DrillState
    ) -> Bool {
        switch requirement {
        case .cursorMoved: return after.cursor != before.cursor
        case .textChanged: return after.text != before.text
        case .modeChanged: return after.mode != before.mode
        case .registerNotEmpty:
            return DrillEngineSupport.registerHasContent(after.register)
                && after.register != before.register
        }
    }

    // MARK: - Arguments + phrasing

    /// Resolves `f`/`t`/`F`/`T`'s target character from the start line.
    /// Returns `.some(nil)` for commands that take no argument, `nil` when no
    /// suitable character exists (site rejected).
    private static func resolveArgument(
        _ kind: DrillArgument, at start: Position, lines: [String]
    ) -> Character?? {
        switch kind {
        case .none:
            return .some(nil)
        case .findForward:
            guard let c = wordStartCharacter(after: start, in: lines) else { return nil }
            return .some(c)
        case .findBack:
            guard let c = wordStartCharacter(before: start, in: lines) else { return nil }
            return .some(c)
        }
    }

    private static func wordStartCharacter(after start: Position, in lines: [String]) -> Character? {
        let chars = Array(lines[start.line])
        var index = start.col + 1
        while index < chars.count {
            let c = chars[index]
            if c != " " && c != "\t" && (chars[index - 1] == " " || chars[index - 1] == "\t") {
                return c
            }
            index += 1
        }
        return nil
    }

    private static func wordStartCharacter(before start: Position, in lines: [String]) -> Character? {
        let chars = Array(lines[start.line])
        var index = start.col - 1
        while index > 0 {
            let c = chars[index]
            if c != " " && c != "\t" && (chars[index - 1] == " " || chars[index - 1] == "\t") {
                return c
            }
            index -= 1
        }
        return nil
    }

    private static func substitute(_ keys: String, char: Character?) -> String {
        guard let char else { return keys }
        return keys.replacingOccurrences(of: "{c}", with: String(char))
    }

    private static func instruction(
        for template: DrillTemplate, word: String, char: Character?, line: Int
    ) -> String {
        var phrase = template.phrase.replacingOccurrences(of: "{word}", with: word)
        if let char {
            phrase = phrase.replacingOccurrences(of: "{char}", with: String(char))
        }
        switch template.locator {
        case .onLine:
            return "\(phrase) on line \(line + 1)."
        case .fromLine:
            return "\(phrase) — you're starting on line \(line + 1)."
        }
    }
}
