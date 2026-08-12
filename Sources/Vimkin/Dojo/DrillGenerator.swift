// DrillGenerator.swift — builds a dojo session: N drills on real corpus
// documents, biased toward the learner's weakest UNLOCKED skills.
//
// Two hard rules (plan U6):
//   1. A locked command can never appear in a generated session. Unlocks come
//      from completed lessons only (ProgressStore/UnlockModel), never XP.
//   2. Weakest first: rusty > learning > mastered at equal score, and lower
//      mastery always outweighs higher mastery within a state.
//
// Deterministic when a seed is injected, system-random otherwise.

import Foundation

public final class DrillGenerator {
    /// Session length target: ~10-15 drills ≈ 2-5 calm minutes.
    public static let defaultSessionLength = 12
    /// Focused mini-session length (the lookup overlay's "Practice this →").
    public static let defaultFocusLength = 6

    // MARK: - Weighting tunables
    //
    // weight(c) = (baseWeight + weaknessGain × deficit(c)) × stateMultiplier(c)
    //   deficit(c) = 1 − masteryScore(c)/100        (continuous, no cliffs)
    //
    // Two properties, both structural rather than statistical:
    //
    //  1. AT EQUAL SCORE the ordering is rusty > learning > mastered/unlearned,
    //     straight from the multipliers.
    //  2. A MASTERED skill is ALWAYS outranked by a non-mastered one. Mastered
    //     means score ≥ 80 ⇒ weight ≤ (0.15 + 0.2) × 1.0 = 0.35, while any
    //     learning skill (score < 80) is ≥ (0.15 + 0.2) × 1.3 = 0.455 and any
    //     rusty skill ≥ 0.56.
    //
    // Across different scores the deficit term dominates on purpose: a nearly
    // forgotten "learning" skill outranks a barely-rusty one, which is the
    // behaviour we want from an adaptive drill picker.

    static let baseWeight = 0.15
    static let weaknessGain = 1.0
    static let rustyMultiplier = 1.6
    static let learningMultiplier = 1.3
    static let unlearnedMultiplier = 1.0
    static let masteredMultiplier = 1.0

    /// Sites harvested per (command, document) pair.
    private static let sitesPerDocument = 4

    private let database: CommandDatabase
    private let documents: [CorpusDocument]
    private let store: ProgressStore
    private var siteCache: [String: [DocumentSite]] = [:]

    private struct DocumentSite {
        let document: CorpusDocument
        let site: DrillSite
    }

    public init(database: CommandDatabase, documents: [CorpusDocument], store: ProgressStore) {
        self.database = database
        self.documents = documents
        self.store = store
    }

    // MARK: - Public surface

    /// Command ids the dojo can drill at all (independent of unlock state).
    public var drillableCommandIDs: [String] {
        DrillCatalog.templates.map(\.commandID)
    }

    /// The selection pool: drillable ∧ unlocked ∧ has at least one site.
    /// Sorted, so generation is deterministic given a seed.
    public var eligibleCommandIDs: [String] {
        let unlocked = store.unlockedCommands
        return drillableCommandIDs
            .filter { unlocked.contains($0) && !sites(for: $0).isEmpty }
            .sorted()
    }

    /// Adaptive selection weight for one command. Higher = drilled more often.
    public func weight(for commandID: String) -> Double {
        Self.weight(
            score: store.masteryScore(commandID: commandID),
            state: store.masteryState(commandID: commandID)
        )
    }

    /// The weighting formula, as a pure function of (score, state).
    public static func weight(score: Double, state: MasteryState) -> Double {
        let deficit = 1 - (score / 100)
        let multiplier: Double
        switch state {
        case .rusty: multiplier = rustyMultiplier
        case .learning: multiplier = learningMultiplier
        case .unlearned: multiplier = unlearnedMultiplier
        case .mastered: multiplier = masteredMultiplier
        }
        return (baseWeight + weaknessGain * deficit) * multiplier
    }

    /// A calm practice session. Same seed ⇒ identical sequence.
    public func makeSession(
        length: Int = DrillGenerator.defaultSessionLength,
        seed: UInt64? = nil
    ) -> [Drill] {
        let pool = eligibleCommandIDs
        guard !pool.isEmpty, length > 0 else { return [] }

        var random = DrillRandomSource(seed: seed)
        var drills: [Drill] = []
        var lastCommandID: String?
        var usedSites: Set<String> = []

        for index in 0..<length {
            // Variety rule: never the same command twice in a row.
            var candidates = pool.filter { $0 != lastCommandID }
            if candidates.isEmpty { candidates = pool }

            let commandID = weightedPick(from: candidates, using: &random)
            guard let drill = makeDrill(
                commandID: commandID, index: index, usedSites: &usedSites, random: &random
            ) else { continue }
            drills.append(drill)
            lastCommandID = commandID
        }
        return drills
    }

    /// A focused mini-session on ONE command — the lookup overlay's
    /// "Practice this →" hand-off. The no-repeats rule is suspended by design
    /// (the learner explicitly asked for this command), and the unlock gate
    /// does not apply: an explicit request outranks curriculum order.
    public func makeFocusedSession(
        commandID: String,
        length: Int = DrillGenerator.defaultFocusLength,
        seed: UInt64? = nil
    ) -> [Drill] {
        guard length > 0, !sites(for: commandID).isEmpty else { return [] }
        var random = DrillRandomSource(seed: seed)
        var usedSites: Set<String> = []
        var drills: [Drill] = []
        for index in 0..<length {
            guard let drill = makeDrill(
                commandID: commandID, index: index, usedSites: &usedSites, random: &random
            ) else { continue }
            drills.append(drill)
        }
        return drills
    }

    /// Whether the dojo can build drills for a command (used by the overlay
    /// hand-off to decide whether "Practice this →" leads anywhere).
    public func canDrill(commandID: String) -> Bool {
        !sites(for: commandID).isEmpty
    }

    // MARK: - Selection

    private func weightedPick(from candidates: [String], using random: inout DrillRandomSource) -> String {
        let weights = candidates.map { weight(for: $0) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates[random.next(upperBound: candidates.count)] }

        var threshold = random.nextUnit() * total
        for (index, weight) in weights.enumerated() {
            threshold -= weight
            if threshold <= 0 { return candidates[index] }
        }
        return candidates[candidates.count - 1]
    }

    private func makeDrill(
        commandID: String,
        index: Int,
        usedSites: inout Set<String>,
        random: inout DrillRandomSource
    ) -> Drill? {
        let all = sites(for: commandID)
        guard !all.isEmpty else { return nil }

        // Prefer a site this session hasn't used yet, so a repeated command
        // shows up somewhere new.
        let fresh = all.enumerated().filter { !usedSites.contains(siteKey(commandID, $0.offset)) }
        let candidates = fresh.isEmpty ? Array(all.enumerated()) : fresh
        let pick = candidates[random.next(upperBound: candidates.count)]
        usedSites.insert(siteKey(commandID, pick.offset))

        let entry = pick.element
        let keys = database.command(id: commandID)?.keys ?? entry.site.solutionKeys
        return Drill(
            id: "\(commandID)@\(entry.document.name):\(entry.site.start.line):\(entry.site.start.col)#\(index)",
            commandID: commandID,
            commandKeys: keys,
            solutionKeys: entry.site.solutionKeys,
            documentName: entry.document.name,
            documentText: entry.document.contents,
            start: entry.site.start,
            instruction: entry.site.instruction,
            goal: entry.site.goal,
            nearMisses: entry.site.nearMisses
        )
    }

    private func siteKey(_ commandID: String, _ offset: Int) -> String {
        "\(commandID)#\(offset)"
    }

    // MARK: - Sites (cached; simulation is the expensive part)

    private func sites(for commandID: String) -> [DocumentSite] {
        if let cached = siteCache[commandID] { return cached }
        guard let template = DrillCatalog.template(for: commandID) else {
            siteCache[commandID] = []
            return []
        }
        let found = documents.flatMap { document in
            DrillSiteFinder
                .sites(for: template, in: document, limit: Self.sitesPerDocument)
                .map { DocumentSite(document: document, site: $0) }
        }
        siteCache[commandID] = found
        return found
    }
}
