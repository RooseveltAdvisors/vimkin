import Foundation
@testable import Vimkin

// Shared scaffolding for the Dojo suites. (`temporaryDirectory()`, `day(_:)`
// and `testCalendar` come from Tests/VimkinTests/Progress/TestSupport.swift —
// same test target, so they are reused here rather than redefined.)

/// A throwaway progress store with the given commands unlocked, on a fixed day.
func makeDojoStore(unlocking commandIDs: [String], on date: Date = day(0)) -> ProgressStore {
    let store = ProgressStore(
        directory: temporaryDirectory(),
        alternateDirectories: [],
        now: { date },
        calendar: testCalendar
    )
    for id in commandIDs { store.markLessonCompleted(commandID: id) }
    return store
}

/// The bundled command database + corpus (the real content, not fixtures).
func dojoContent() throws -> (database: CommandDatabase, documents: [CorpusDocument]) {
    (try CommandDatabase.load(), try Corpus.loadAll())
}

/// A generator over the real content with the given commands unlocked.
func makeDojoGenerator(
    unlocking commandIDs: [String], store: ProgressStore? = nil
) throws -> (generator: DrillGenerator, store: ProgressStore) {
    let content = try dojoContent()
    let store = store ?? makeDojoStore(unlocking: commandIDs)
    return (
        DrillGenerator(database: content.database, documents: content.documents, store: store),
        store
    )
}

/// Every command the dojo knows how to drill.
var allDrillableIDs: [String] { DrillCatalog.templates.map(\.commandID) }

/// Replays `keys` against a drill from its pristine start state and returns the
/// attempt — exactly what the dojo hands the judge after each command.
func replay(_ keys: String, on drill: Drill) -> DrillAttempt? {
    guard var engine = DrillEngineSupport.engine(text: drill.documentText, at: drill.start) else {
        return nil
    }
    let before = DrillState(engine: engine)
    let events = engine.feed(keys: keys)
    return DrillAttempt(events: events, before: before, after: DrillState(engine: engine))
}

/// Drives one attempt through a live DrillSession (same path as the UI).
@discardableResult
func submitAttempt(_ keys: String, on drill: Drill, in session: DrillSession) -> DrillJudgement? {
    guard let attempt = replay(keys, on: drill) else { return nil }
    return session.submit(attempt)
}

/// Drives a command's mastery score up with repeated correct reps.
func practiceCorrect(_ store: ProgressStore, _ commandID: String, times: Int) {
    for _ in 0..<times { store.recordRep(commandID: commandID, outcome: .correct) }
}
