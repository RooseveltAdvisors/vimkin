// Level.swift — the adventure game's level model (plan U7).
//
// A level IS a document. The body of the level file becomes the terrain the
// cursor-spirit walks; the YAML front-matter declares which commands the level
// hands the player, where the Vimkins are trapped, and what frees each one.
//
// Pure Swift + Foundation: no SpriteKit, no SwiftUI, no engine mutation. The
// game logic (GameState) evaluates these definitions; the scene only draws them.

import Foundation

/// What frees a Vimkin (or satisfies an extra level goal).
///
/// Deliberately a small, closed vocabulary: every condition is decidable from
/// a `VimEngine` snapshot alone, so goal evaluation is a pure function of
/// engine state and can never depend on how the player got there.
public enum RescueCondition: Equatable, Hashable, Sendable {
    /// The cursor lands exactly on this buffer position.
    case cursorReaches(Position)
    /// The text no longer appears anywhere in the document (deleted/changed away).
    case textRemoved(String)
    /// The text now appears in the document (typed/restored).
    case textPresent(String)
    /// The unnamed register holds this text (yanked/deleted into it).
    case registerContains(String)

    /// Front-matter keyword for this condition.
    public var keyword: String {
        switch self {
        case .cursorReaches: return "reach"
        case .textRemoved: return "removed"
        case .textPresent: return "written"
        case .registerContains: return "yanked"
        }
    }
}

/// One trapped Vimkin: where it sits in the document, and what frees it.
public struct Vimkin: Equatable, Hashable, Sendable, Identifiable {
    /// Unique within the level (also the creature's name — they have names).
    public let id: String
    /// Where the creature is drawn in the document grid.
    public let position: Position
    /// What the player must do to free it.
    public let condition: RescueCondition
    /// One line of flavor shown when it pops free. Optional.
    public let cheer: String?

    public init(id: String, position: Position, condition: RescueCondition, cheer: String? = nil) {
        self.id = id
        self.position = position
        self.condition = condition
        self.cheer = cheer
    }
}

/// One World 1 level.
public struct Level: Equatable, Sendable, Identifiable {
    /// Stable slug, e.g. `"w1-01-ink-and-margins"`.
    public let id: String
    public let title: String
    /// 1-based position in the world (contiguous — pinned by a schema test).
    public let order: Int
    /// One skippable story line, shown before the level starts.
    public let intro: String
    /// Human-readable summary of what this level teaches (HUD + world map).
    public let teaches: String
    /// `VimCommand.id`s this level hands the player. EVERY other key is locked
    /// by `LockFilter` — this list is the level's whole toolkit.
    public let allowedCommandIDs: [String]
    /// Keystroke par. Beating it is a flourish, never a gate (accuracy first).
    public let par: Int
    /// A canonical key sequence that beats the level using only `allowed`
    /// commands. Proven by `LevelBeatabilityTests`; also powers a future
    /// "show me" affordance.
    public let solution: String
    public let vimkins: [Vimkin]
    /// Extra completion conditions beyond rescuing every Vimkin (boss levels).
    public let extraGoals: [RescueCondition]
    /// The document body — the terrain.
    public let document: String

    public init(
        id: String,
        title: String,
        order: Int,
        intro: String,
        teaches: String,
        allowedCommandIDs: [String],
        par: Int,
        solution: String,
        vimkins: [Vimkin],
        extraGoals: [RescueCondition],
        document: String
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.intro = intro
        self.teaches = teaches
        self.allowedCommandIDs = allowedCommandIDs
        self.par = par
        self.solution = solution
        self.vimkins = vimkins
        self.extraGoals = extraGoals
        self.document = document
    }

    /// Every condition that must hold for the level to be complete.
    public var allConditions: [RescueCondition] {
        vimkins.map(\.condition) + extraGoals
    }
}
