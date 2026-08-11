import Foundation

/// Unlock computation. STRUCTURAL INVARIANT (plan R7 / KTD 6): unlocks are a
/// function of completed lessons ONLY — no XP parameter exists anywhere in
/// this API, so XP cannot gate progression even by accident. Tests pin the
/// signature at compile time.
public enum UnlockModel {
    /// The set of unlocked command ids given the lessons completed so far.
    /// (v1: completing a command's lesson unlocks that command. Mastery-based
    /// refinements, if ever needed, extend this signature with mastery — never
    /// with XP.)
    public static func unlockedCommands(completedLessons: Set<String>) -> Set<String> {
        completedLessons
    }
}
