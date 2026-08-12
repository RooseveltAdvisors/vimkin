// ArcadeModel.swift — the daily run's orchestrator: owns the gauntlet builder,
// the running `ArcadeRunSession`, the editor the player types into, and the
// one-run-per-day gate.
//
// Observation-only (no SwiftUI import), so the whole surface is testable
// headless — including the "you already played today" state, which is the
// behaviour most likely to rot silently.

import Foundation
import Observation

@MainActor
@Observable
public final class ArcadeModel {
    public enum Phase: Equatable, Sendable {
        /// The front door: today's card, or today's finished result.
        case idle
        case running
        case result
    }

    // MARK: - Observable state

    public private(set) var phase: Phase = .idle
    public private(set) var session: ArcadeRunSession?
    /// The editor the current drill is played in. Replaced per drill, and after
    /// a miss, so the document is always pristine on a retry.
    public private(set) var editor: EditorSession?
    /// Bumped whenever `editor` is replaced, so SwiftUI can re-key the view.
    public private(set) var editorGeneration: Int = 0
    public private(set) var feedback: DrillJudgement?
    /// The clear that just landed — the number the HUD pops.
    public private(set) var lastHit: ArcadeHit?
    /// Increments on every clear, so an identical score twice in a row still
    /// animates (same trick as `JuiceConductor.pulse`).
    public private(set) var hitPulse: Int = 0
    /// The result of the run that just ended (scored or practice).
    public private(set) var lastResult: ArcadeRunResult?
    /// True when the run that just ended went onto the leaderboard.
    public private(set) var lastResultWasRecorded: Bool = false

    // MARK: - Dependencies

    public let builder: ArcadeRunBuilder
    public let leaderboard: ArcadeLeaderboardStore
    private let now: () -> Date
    private let calendar: Calendar
    private let length: Int
    private let timeLimit: TimeInterval

    public init(
        database: CommandDatabase,
        documents: [CorpusDocument],
        store: ProgressStore,
        leaderboard: ArcadeLeaderboardStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        length: Int = ArcadeRun.defaultLength,
        timeLimit: TimeInterval = ArcadeRun.defaultTimeLimit
    ) {
        self.builder = ArcadeRunBuilder(
            generator: DrillGenerator(database: database, documents: documents, store: store)
        )
        self.leaderboard = leaderboard
        self.now = now
        self.calendar = calendar
        self.length = length
        self.timeLimit = timeLimit
    }

    /// The app-facing constructor: bundled content + the real stores. Content
    /// failures degrade to an empty, honest arcade rather than crashing.
    public static func bundled(
        store: ProgressStore = ProgressStore(),
        leaderboard: ArcadeLeaderboardStore = ArcadeLeaderboardStore()
    ) -> ArcadeModel {
        let database = (try? CommandDatabase.load()) ?? CommandDatabase(commands: [])
        let documents = (try? Corpus.loadAll()) ?? []
        return ArcadeModel(
            database: database, documents: documents, store: store, leaderboard: leaderboard
        )
    }

    // MARK: - Today

    public var today: String { ArcadeDay.key(for: now(), calendar: calendar) }

    /// Today's recorded run, if it has already been played.
    public var todaysResult: ArcadeRunResult? { leaderboard.result(day: today) }

    /// False once today's run is in the books — the come-back-tomorrow state.
    public var canPlayScoredRun: Bool { todaysResult == nil }

    /// True when there is anything unlocked to build a gauntlet from.
    public var isReady: Bool { !builder.pool.isEmpty }

    /// Today's gauntlet, without starting it (the front-door preview).
    public var todaysGauntlet: [Drill] { builder.gauntlet(day: today, length: length) }

    public var currentDrill: Drill? { session?.currentDrill }

    // MARK: - Run lifecycle

    /// Starts today's SCORED run. A no-op once today has been played — the day
    /// is already in the books and replaying it must not re-score.
    public func startDailyRun() {
        guard canPlayScoredRun else {
            showTodaysRecordedResult()
            return
        }
        begin(scored: true)
    }

    /// Replays today's identical gauntlet unscored. Always available — practice
    /// is never rationed; only the leaderboard entry is.
    public func startPracticeRun() {
        begin(scored: false)
    }

    /// Back to the front door.
    public func reset() {
        detachEditor()
        session = nil
        feedback = nil
        lastHit = nil
        lastResult = nil
        lastResultWasRecorded = false
        phase = .idle
    }

    /// Bail out mid-gauntlet. A scored run still counts — you played today.
    public func endRun() {
        guard let session else { return }
        session.end()
        finish(session)
    }

    /// Move past this drill unscored (breaks the combo).
    public func skipDrill() {
        session?.skipCurrentDrill()
        feedback = nil
        presentCurrentDrill()
    }

    /// Drive the clock from the UI's display timer. Ends the run the moment the
    /// gauntlet clock expires, so a stalled player cannot sit on a drill forever.
    public func tick() {
        guard phase == .running, let session else { return }
        if session.isFinished { finish(session) }
    }

    // MARK: - Internals

    private func begin(scored: Bool) {
        feedback = nil
        lastHit = nil
        lastResult = nil
        lastResultWasRecorded = false

        let drills = builder.gauntlet(day: today, length: length)
        let session = ArcadeRunSession(
            drills: drills,
            day: today,
            isScored: scored,
            timeLimit: timeLimit,
            now: now
        )
        self.session = session

        guard !drills.isEmpty else {
            finish(session)
            return
        }
        phase = .running
        session.begin()
        presentCurrentDrill()
    }

    private func showTodaysRecordedResult() {
        guard let recorded = todaysResult else { return }
        detachEditor()
        session = nil
        lastResult = recorded
        // Not recorded BY THIS VISIT — it was already there.
        lastResultWasRecorded = false
        phase = .result
    }

    private func presentCurrentDrill() {
        guard let session else { return }
        guard let drill = session.currentDrill else {
            finish(session)
            return
        }
        attachEditor(for: drill)
    }

    /// Idempotent: a run is recorded at most once, however many paths (the last
    /// clear, the clock tick, a bail-out) arrive at the finish line.
    private func finish(_ session: ArcadeRunSession) {
        guard phase != .result else { return }
        detachEditor()
        session.end()
        let result = session.result()
        lastResult = result
        // An empty gauntlet (nothing unlocked yet) is not a run — it must not
        // burn the day or land a 0 on the board.
        lastResultWasRecorded = session.isScored
            && !session.drills.isEmpty
            && leaderboard.record(result)
        phase = .result
    }

    private func attachEditor(for drill: Drill?) {
        detachEditor()
        guard let drill else { return }
        let editor = EditorSession(text: drill.documentText, documentName: drill.documentName)
        // Position the cursor BEFORE wiring the judge, so setup keys are never
        // mistaken for an attempt.
        editor.feed(keys: DrillEngineSupport.positioningKeys(to: drill.start))
        editor.onEvents = { [weak self] events in
            MainActor.assumeIsolated { self?.judge(events) }
        }
        self.editor = editor
        editorGeneration += 1
    }

    private func detachEditor() {
        editor?.onEvents = nil
        editor = nil
    }

    private func judge(_ events: [CommandEvent]) {
        guard let session, let drill = session.currentDrill, let editor else { return }

        let before = DrillState(
            text: drill.documentText, cursor: drill.start, mode: .normal, register: nil
        )
        let attempt = DrillAttempt(
            events: events, before: before, after: DrillState(session: editor)
        )

        guard let judgement = session.submit(attempt) else {
            finish(session)
            return
        }
        feedback = judgement

        if judgement.isCorrect {
            if let hit = session.lastHit {
                lastHit = hit
                hitPulse &+= 1
            }
            presentCurrentDrill()
        } else {
            // Same drill, clean document. Under pressure the cost is the clock.
            attachEditor(for: drill)
        }
    }
}
