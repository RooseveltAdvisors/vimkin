// DrillCatalog.swift — which commands the dojo can drill, how each one is
// phrased in plain English, and which sibling commands are its classic
// confusions (so a wrong attempt can be *named*, not just marked wrong).
//
// Only commands whose keys form a COMPLETE, standalone executable command are
// drillable. Bare operators (`d`, `c`, `y`) and bare text objects (`iw`, `i"`)
// are deliberately absent: they are half a sentence. Their grammar records
// (`diw`, `ci"`, …) carry them instead. `;` `,` `p` `P` `u` `Esc` are absent
// because they need a prior command to be meaningful — they belong to the
// tutorial and the game, not to a single-command drill.

import Foundation

/// How a drill's phrase locates the work in the document.
enum DrillLocator: Sendable {
    /// "… on line 12." — used when the command edits text on that line.
    case onLine
    /// "… — you're starting on line 12." — used for motions.
    case fromLine
}

/// An extra argument the command consumes, resolved per drill site.
enum DrillArgument: Sendable {
    case none
    /// `f` / `t`: a character occurring later on the start line.
    case findForward
    /// `F` / `T`: a character occurring earlier on the start line.
    case findBack
}

/// What makes a candidate site non-degenerate for this command.
enum DrillRequirement: Sendable {
    case cursorMoved
    case textChanged
    case modeChanged
    /// The command must have captured something (delete/change/yank drills).
    case registerNotEmpty
}

/// A sibling command learners reach for by mistake.
struct Confusable: Sendable {
    /// Keys, `{c}` substituted with the drill's find argument.
    let keys: String
    /// Completes "…; `dw` <note>."
    let note: String
}

/// One drillable command.
struct DrillTemplate: Sendable {
    let commandID: String
    /// Keys with an optional `{c}` placeholder for the find argument.
    let keys: String
    let argument: DrillArgument
    /// Plain-English imperative. `{word}` = the text the command operates on,
    /// `{char}` = the find argument.
    let phrase: String
    /// Completes "`diw` <note>" in near-miss feedback.
    let note: String
    let locator: DrillLocator
    let requirement: DrillRequirement
    let confusables: [Confusable]

    init(
        _ commandID: String,
        keys: String,
        phrase: String,
        note: String,
        locator: DrillLocator = .onLine,
        requirement: DrillRequirement = .textChanged,
        argument: DrillArgument = .none,
        confusables: [Confusable] = []
    ) {
        self.commandID = commandID
        self.keys = keys
        self.argument = argument
        self.phrase = phrase
        self.note = note
        self.locator = locator
        self.requirement = requirement
        self.confusables = confusables
    }
}

enum DrillCatalog {
    /// Every drillable command, in curriculum order.
    static let templates: [DrillTemplate] = [
        // MARK: Tier 1 — survive

        DrillTemplate(
            "motion.left", keys: "h",
            phrase: "Move one character to the left",
            note: "steps one character left",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "l", note: "steps to the right")]
        ),
        DrillTemplate(
            "motion.down", keys: "j",
            phrase: "Move down one line",
            note: "goes down a line",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "k", note: "goes up a line")]
        ),
        DrillTemplate(
            "motion.up", keys: "k",
            phrase: "Move up one line",
            note: "goes up a line",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "j", note: "goes down a line")]
        ),
        DrillTemplate(
            "motion.right", keys: "l",
            phrase: "Move one character to the right",
            note: "steps one character right",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "h", note: "steps to the left")]
        ),
        DrillTemplate(
            "action.insert-before", keys: "i",
            phrase: "Start typing right where the cursor is",
            note: "inserts just before the character under the cursor",
            locator: .fromLine, requirement: .modeChanged,
            confusables: [Confusable(keys: "a", note: "starts one character further right")]
        ),
        DrillTemplate(
            "action.insert-after", keys: "a",
            phrase: "Start typing just after the cursor",
            note: "steps one character right, then inserts",
            locator: .fromLine, requirement: .modeChanged,
            confusables: [Confusable(keys: "i", note: "inserts before the cursor, not after")]
        ),
        DrillTemplate(
            "action.insert-line-start", keys: "I",
            phrase: "Jump to the first text on this line and start typing",
            note: "jumps to the first non-blank character first",
            locator: .fromLine, requirement: .modeChanged,
            confusables: [
                Confusable(keys: "i", note: "inserts wherever the cursor already sits"),
                Confusable(keys: "A", note: "inserts at the END of the line"),
            ]
        ),
        DrillTemplate(
            "action.insert-line-end", keys: "A",
            phrase: "Jump to the end of this line and start typing",
            note: "jumps past the last character first",
            locator: .fromLine, requirement: .modeChanged,
            confusables: [
                Confusable(keys: "a", note: "only steps one character right"),
                Confusable(keys: "I", note: "goes to the START of the line"),
            ]
        ),
        DrillTemplate(
            "action.open-below", keys: "o",
            phrase: "Open a fresh line below this one and start typing",
            note: "opens the new line BELOW",
            locator: .fromLine,
            confusables: [Confusable(keys: "O", note: "opens the new line above")]
        ),
        DrillTemplate(
            "action.open-above", keys: "O",
            phrase: "Open a fresh line above this one and start typing",
            note: "opens the new line ABOVE",
            locator: .fromLine,
            confusables: [Confusable(keys: "o", note: "opens the new line below")]
        ),

        // MARK: Tier 2 — navigate

        DrillTemplate(
            "motion.word-forward", keys: "w",
            phrase: "Move to the start of the next word",
            note: "lands on the START of the next word",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [
                Confusable(keys: "e", note: "lands on the end of the word you're on"),
                Confusable(keys: "b", note: "goes backwards a word"),
            ]
        ),
        DrillTemplate(
            "motion.word-back", keys: "b",
            phrase: "Move back to the start of the previous word",
            note: "goes back to the start of the word before",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "w", note: "goes forward instead")]
        ),
        DrillTemplate(
            "motion.word-end", keys: "e",
            phrase: "Move to the last character of this word",
            note: "lands on the LAST character of the word",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "w", note: "lands on the start of the next word")]
        ),
        DrillTemplate(
            "motion.line-start", keys: "0",
            phrase: "Jump to the very start of the line",
            note: "goes all the way to column one, indentation and all",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "^", note: "stops at the first non-blank character")]
        ),
        DrillTemplate(
            "motion.first-char", keys: "^",
            phrase: "Jump to the first non-blank character on the line",
            note: "skips the indentation and stops at the first real character",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "0", note: "goes to column one, before the indentation")]
        ),
        DrillTemplate(
            "motion.line-end", keys: "$",
            phrase: "Jump to the end of the line",
            note: "lands on the last character of the line",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "0", note: "goes to the start of the line")]
        ),
        DrillTemplate(
            "motion.file-top", keys: "gg",
            phrase: "Jump to the very top of the document",
            note: "jumps to the FIRST line",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "G", note: "jumps to the last line")]
        ),
        DrillTemplate(
            "motion.file-bottom", keys: "G",
            phrase: "Jump to the last line of the document",
            note: "jumps to the LAST line",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "gg", note: "jumps to the first line")]
        ),
        DrillTemplate(
            "motion.find-forward", keys: "f{c}",
            phrase: "Jump forward to the next `{char}` on this line",
            note: "lands ON the character you asked for",
            locator: .fromLine, requirement: .cursorMoved, argument: .findForward,
            confusables: [Confusable(keys: "t{c}", note: "stops one character short of it")]
        ),
        DrillTemplate(
            "motion.find-back", keys: "F{c}",
            phrase: "Jump back to the previous `{char}` on this line",
            note: "lands ON the character, searching backwards",
            locator: .fromLine, requirement: .cursorMoved, argument: .findBack,
            confusables: [Confusable(keys: "T{c}", note: "stops one character after it")]
        ),
        DrillTemplate(
            "motion.till-forward", keys: "t{c}",
            phrase: "Jump forward to just before the next `{char}` on this line",
            note: "stops one character SHORT of it",
            locator: .fromLine, requirement: .cursorMoved, argument: .findForward,
            confusables: [Confusable(keys: "f{c}", note: "lands right on the character")]
        ),
        DrillTemplate(
            "motion.till-back", keys: "T{c}",
            phrase: "Jump back to just after the previous `{char}` on this line",
            note: "stops one character after it, searching backwards",
            locator: .fromLine, requirement: .cursorMoved, argument: .findBack,
            confusables: [Confusable(keys: "F{c}", note: "lands right on the character")]
        ),

        // MARK: Tier 3 — edit verbs

        DrillTemplate(
            "action.delete-char", keys: "x",
            phrase: "Delete the single character under the cursor",
            note: "removes exactly one character",
            confusables: [Confusable(keys: "dd", note: "removes the entire line")]
        ),
        DrillTemplate(
            "action.delete-line", keys: "dd",
            phrase: "Delete this whole line",
            note: "removes the entire line",
            requirement: .registerNotEmpty,
            confusables: [Confusable(keys: "x", note: "only removes one character")]
        ),
        DrillTemplate(
            "action.change-line", keys: "cc",
            phrase: "Clear this line and start typing a new one",
            note: "empties the line and leaves you in Insert mode",
            requirement: .registerNotEmpty,
            confusables: [Confusable(keys: "dd", note: "deletes the line and stays in Normal mode")]
        ),
        DrillTemplate(
            "action.yank-line", keys: "yy",
            phrase: "Copy this whole line",
            note: "copies the line and leaves it in place",
            requirement: .registerNotEmpty,
            confusables: [Confusable(keys: "dd", note: "deletes the line instead of copying it")]
        ),
        DrillTemplate(
            "grammar.count-motion", keys: "3w",
            phrase: "Move forward three words in one go",
            note: "repeats the word motion three times",
            locator: .fromLine, requirement: .cursorMoved,
            confusables: [Confusable(keys: "w", note: "moves just one word")]
        ),
        DrillTemplate(
            "grammar.count-delete-lines", keys: "2dd",
            phrase: "Delete two lines at once",
            note: "takes two lines in one command",
            requirement: .registerNotEmpty,
            confusables: [Confusable(keys: "dd", note: "only takes one line")]
        ),

        // MARK: Tier 4 — text-object grammar

        DrillTemplate(
            "grammar.delete-inner-word", keys: "diw",
            phrase: "Delete the word `{word}`",
            note: "deletes the whole word under the cursor, wherever you are inside it",
            requirement: .registerNotEmpty,
            confusables: [
                Confusable(keys: "dw", note: "deletes from the cursor to the start of the next word"),
                Confusable(keys: "daw", note: "also swallows the space after the word"),
            ]
        ),
        DrillTemplate(
            "grammar.delete-inside-quotes", keys: "di\"",
            phrase: "Delete `{word}` from between the quotes",
            note: "empties the quotes and leaves them standing",
            requirement: .registerNotEmpty,
            confusables: [
                Confusable(keys: "da\"", note: "takes the quote marks with it"),
                Confusable(keys: "dw", note: "only reaches to the next word"),
            ]
        ),
        DrillTemplate(
            "grammar.change-inside-quotes", keys: "ci\"",
            phrase: "Replace `{word}` between the quotes",
            note: "clears the quotes and drops you straight into Insert mode",
            requirement: .registerNotEmpty,
            confusables: [
                Confusable(keys: "di\"", note: "clears them but leaves you in Normal mode"),
                Confusable(keys: "ca\"", note: "eats the quote marks too"),
            ]
        ),
        DrillTemplate(
            "grammar.yank-around-parens", keys: "ya(",
            phrase: "Copy the brackets and everything inside them",
            note: "copies the brackets as well as their contents",
            requirement: .registerNotEmpty,
            confusables: [Confusable(keys: "yi(", note: "copies only what's inside the brackets")]
        ),
        DrillTemplate(
            "grammar.delete-around-paragraph", keys: "dap",
            phrase: "Delete this whole paragraph",
            note: "takes the paragraph and the blank line after it",
            requirement: .registerNotEmpty,
            confusables: [Confusable(keys: "dip", note: "leaves the blank line behind")]
        ),
    ]

    /// Drillable command ids, for unlock/weighting lookups.
    static let drillableCommandIDs: Set<String> = Set(templates.map(\.commandID))

    static func template(for commandID: String) -> DrillTemplate? {
        templates.first { $0.commandID == commandID }
    }
}
