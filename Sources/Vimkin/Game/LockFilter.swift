// LockFilter.swift — the skill gate (plan U7 / R2).
//
// A level hands the player a toolkit (`allowed` command ids). Every other key is
// intercepted BEFORE it reaches the engine, so a not-yet-learned command cannot
// change the game state even by accident. Blocking is never a failure: the
// player gets a friendly shimmer and a pointer to the lesson that teaches it.
//
// Where the toolkit comes from (the resolution of "level allow-list" vs
// "ProgressStore unlocks"): the LEVEL is the authority on what is usable inside
// it — a level's puzzle is only a puzzle if the intended motions are the ones
// available, and a fresh profile must still be able to play the headline mode.
// The ProgressStore is consulted for MESSAGING only: if the player has already
// learned the blocked command, the toast says "not part of this level's
// toolkit"; if not, it says which lesson teaches it.
//
// Pure Swift: no SwiftUI import. `KeyDecision` lives in the shared KeyCapture
// component, which the game wraps around its SpriteView.

import Foundation

public struct LockFilter: Equatable, Sendable {
    /// Characters this level accepts in normal/visual/operator-pending mode.
    public let allowedCharacters: Set<Character>
    /// Per-character explanation shown when a key is blocked.
    public let blockReasons: [Character: String]
    /// Fallback message for a character no command in the database claims.
    public let unknownKeyReason: String
    /// When true the gate is open: every key passes. Used for sandbox play and
    /// as the fail-open default when no command database is available — a
    /// missing database must never leave the player unable to press anything.
    public let isOpen: Bool

    public init(
        allowedCharacters: Set<Character>,
        blockReasons: [Character: String],
        unknownKeyReason: String = "That key isn't part of Vimkin's world yet.",
        isOpen: Bool = false
    ) {
        self.allowedCharacters = allowedCharacters
        self.blockReasons = blockReasons
        self.unknownKeyReason = unknownKeyReason
        self.isOpen = isOpen
    }

    /// A gate that blocks nothing.
    public static let open = LockFilter(
        allowedCharacters: [], blockReasons: [:], isOpen: true
    )

    // MARK: - Construction

    /// Builds the filter for a level.
    ///
    /// - Parameters:
    ///   - level: the level whose `allowed` ids form the toolkit.
    ///   - database: the command database (id → keys, and the lesson pointers).
    ///   - unlockedCommandIDs: the player's tutorial unlocks — messaging only,
    ///     never widens or narrows what the level accepts.
    public static func make(
        level: Level,
        database: CommandDatabase,
        unlockedCommandIDs: Set<String> = []
    ) -> LockFilter {
        var allowed: Set<Character> = []
        for id in level.allowedCommandIDs {
            guard let command = database.command(id: id) else { continue }
            allowed.formUnion(inputCharacters(for: command))
        }

        // Every character some command in the database owns, mapped to the
        // lowest-tier command that claims it — that is the lesson to point at.
        var claim: [Character: VimCommand] = [:]
        for command in database.commands {
            for c in inputCharacters(for: command) where !allowed.contains(c) {
                if let existing = claim[c] {
                    let better = (command.tier, command.lesson) < (existing.tier, existing.lesson)
                    if better { claim[c] = command }
                } else {
                    claim[c] = command
                }
            }
        }

        var reasons: [Character: String] = [:]
        for (c, command) in claim {
            if unlockedCommandIDs.contains(command.id) {
                reasons[c] = "`\(command.keys)` works elsewhere — but this level's "
                    + "toolkit is \(level.teaches)."
            } else {
                reasons[c] = "`\(command.keys)` — \(command.title). "
                    + "You'll learn this in Tier \(command.tier), Lesson \(command.lesson)."
            }
        }

        return LockFilter(allowedCharacters: allowed, blockReasons: reasons)
    }

    /// The characters a command consumes as its FIRST keystrokes.
    /// - `Esc` is a named key, not the letters E, s, c.
    /// - `:w` only claims `:` — the rest is typed at the `:` prompt, where the
    ///   engine is taking literal input anyway.
    /// - `gg` claims `g`; `di"` claims `d` (its `i` and `"` arrive while the
    ///   engine is mid-command, which the filter lets through).
    static func inputCharacters(for command: VimCommand) -> Set<Character> {
        if command.keys == "Esc" { return [] }
        if command.keys.hasPrefix(":") { return [":"] }
        guard let first = command.keys.first else { return [] }
        // A placeholder record like `m{a-z}` claims only its literal prefix.
        if let brace = command.keys.firstIndex(of: "{") {
            return Set(command.keys[command.keys.startIndex..<brace])
        }
        // Doubled forms (dd, yy) and grammar examples (3w, diw) claim their
        // first key only; the remainder arrives mid-command.
        return [first]
    }

    // MARK: - Decision

    /// Verdict for one key.
    ///
    /// - Parameter awaitingLiteral: true when the engine is mid-command or in a
    ///   literal-input mode (insert, `:` prompt, waiting for an `f`/`t` target
    ///   or a text-object key). Those keystrokes are ARGUMENTS, not commands, so
    ///   the gate must let them through — otherwise `f"` could never be typed.
    public func decision(for key: KeyInput, awaitingLiteral: Bool) -> KeyDecision {
        switch key {
        case .escape:
            // Esc is never locked: the player must always be able to come home.
            return .allow
        case .enter:
            // Enter is a newline in insert mode and a no-op elsewhere; never a
            // locked command, so it is never gated.
            return .allow
        case .char(let c):
            if isOpen || awaitingLiteral { return .allow }
            if allowedCharacters.contains(c) { return .allow }
            return .block(reason: blockReasons[c] ?? unknownKeyReason)
        }
    }
}

extension VimEngine {
    /// True when the next keystroke is an ARGUMENT rather than a command:
    /// insert mode, the `:` prompt, an `f`/`t` waiting for its target, or an
    /// `i`/`a` waiting for its text-object key.
    ///
    /// Read-only view of engine state — Engine/ itself is untouched (the same
    /// technique the tutorial uses for `isMidCommand`).
    var isAwaitingLiteralKey: Bool {
        if mode == .insert || mode == .commandLine { return true }
        return pending.awaitingFindChar != nil || pending.awaitingObjectChar != nil
    }
}
