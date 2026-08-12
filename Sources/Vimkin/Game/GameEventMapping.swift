// GameEventMapping.swift — CommandEvent → command id / complexity (plan U7).
//
// Playing the game IS practice, so a delivered command should feed the same
// mastery + XP spine the tutorial and dojo write to. That needs the event
// mapped back to a `VimCommand.id`.
//
// Honest limitation, stated rather than faked: `CommandEvent` reports
// `.enterInsert` for i / a / I / A / o / O without distinguishing which key was
// pressed, so mode events map to NO command id and record no rep. Recording a
// guessed id would corrupt the mastery model, which is worse than recording
// nothing. Motions, operators, and actions all map exactly.
//
// U8 note: this is also the natural place to resolve an event to a juice tier —
// `CommandEvent.category` is the tier key, and `complexity(for:)` below is the
// existing three-step ladder.

import Foundation

public enum GameEventMapping {

    /// The `VimCommand.id` a completed event corresponds to, if one exists.
    public static func commandID(for event: CommandEvent) -> String? {
        switch event.verb {
        case .move:
            guard case .motion(let motion)? = event.target else { return nil }
            return commandID(for: motion)
        case .deleteChar: return "action.delete-char"
        case .undo: return "action.undo"
        case .put: return "action.paste-after"
        case .putBefore: return "action.paste-before"
        case .delete:
            if case .line? = event.target { return "action.delete-line" }
            return "operator.delete"
        case .change:
            if case .line? = event.target { return "action.change-line" }
            return "operator.change"
        case .yank:
            if case .line? = event.target { return "action.yank-line" }
            return "operator.yank"
        case .enterVisual, .leaveVisual: return "action.visual"
        case .write: return "cmd.write"
        case .quit: return "cmd.quit"
        case .writeQuit: return "cmd.write-quit"
        case .enterInsert, .leaveInsert:
            // Ambiguous by construction — see the file header.
            return nil
        }
    }

    public static func commandID(for motion: Motion) -> String {
        switch motion {
        case .left: return "motion.left"
        case .down: return "motion.down"
        case .up: return "motion.up"
        case .right: return "motion.right"
        case .wordForward: return "motion.word-forward"
        case .wordBackward: return "motion.word-back"
        case .wordEnd: return "motion.word-end"
        case .lineStart: return "motion.line-start"
        case .lineEnd: return "motion.line-end"
        case .firstNonBlank: return "motion.first-char"
        case .fileStart: return "motion.file-top"
        case .fileEnd: return "motion.file-bottom"
        case .find: return "motion.find-forward"
        case .findBack: return "motion.find-back"
        case .till: return "motion.till-forward"
        case .tillBack: return "motion.till-back"
        case .repeatFind: return "motion.repeat-find"
        case .repeatFindReverse: return "motion.repeat-find-reverse"
        }
    }

    /// XP/juice tier for an event. Mode transitions and `:` commands earn
    /// nothing — they are navigation of the app, not of the document.
    public static func complexity(for event: CommandEvent) -> CommandComplexity? {
        switch event.category {
        case .singleMotion, .action: return .singleMotion
        case .operatorMotion: return .operatorMotion
        case .fullGrammar: return .fullGrammar
        case .mode, .commandLine: return nil
        }
    }
}
