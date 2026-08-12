import Foundation
@testable import Vimkin

// Shared scaffolding for the adventure-game suites. (`temporaryDirectory()`,
// `day(_:)` and `testCalendar` come from Tests/VimkinTests/Progress/TestSupport.swift
// — same test target, so they are reused here rather than redefined.)

/// The bundled World 1 levels (the real content, not fixtures).
func world1() throws -> LevelDatabase {
    try LevelDatabase.loadWorld1()
}

/// The bundled command database.
func gameCommands() throws -> CommandDatabase {
    try CommandDatabase.load()
}

/// A GameState for a level with its real skill gate in place.
func gatedState(
    for level: Level,
    unlocking unlockedIDs: Set<String> = []
) throws -> GameState {
    let filter = LockFilter.make(
        level: level, database: try gameCommands(), unlockedCommandIDs: unlockedIDs
    )
    return GameState(level: level, lockFilter: filter)
}

/// A throwaway progress store on a fixed day (adventure runs write reps to it).
func makeGameProgressStore(on date: Date = day(0)) -> ProgressStore {
    ProgressStore(
        directory: temporaryDirectory(),
        alternateDirectories: [],
        now: { date },
        calendar: testCalendar
    )
}

/// A throwaway level-results store.
func makeLevelResultsStore() -> GameProgressStore {
    GameProgressStore(directory: temporaryDirectory())
}

/// A single level built inline, for tests that need a specific shape.
func makeLevel(
    id: String = "test-level",
    title: String = "Test Level",
    order: Int = 1,
    allowed: [String] = [],
    par: Int = 10,
    solution: String = "",
    vimkins: [Vimkin] = [],
    extraGoals: [RescueCondition] = [],
    document: String
) -> Level {
    Level(
        id: id,
        title: title,
        order: order,
        intro: "intro",
        teaches: "testing",
        allowedCommandIDs: allowed,
        par: par,
        solution: solution,
        vimkins: vimkins,
        extraGoals: extraGoals,
        document: document
    )
}
