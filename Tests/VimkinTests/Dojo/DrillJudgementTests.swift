import Foundation
import Testing
@testable import Vimkin

@Suite("Dojo: success predicate + near-miss classification")
struct DrillJudgementTests {

    private func focusedDrills(_ commandID: String, seed: UInt64 = 5, length: Int = 4) throws -> [Drill] {
        let (generator, _) = try makeDojoGenerator(unlocking: [commandID])
        return generator.makeFocusedSession(commandID: commandID, length: length, seed: seed)
    }

    // MARK: - diw vs dw (the canonical confusion)

    @Test("target diw: feeding diw succeeds")
    func diwSucceeds() throws {
        let drills = try focusedDrills("grammar.delete-inner-word")
        #expect(!drills.isEmpty)
        for drill in drills {
            let attempt = try #require(replay(drill.solutionKeys, on: drill))
            #expect(drill.succeeds(attempt), "\(drill.id) did not accept its own solution")
            #expect(drill.evaluate(attempt) == .correct)
        }
    }

    @Test("target diw: feeding dw is a NEAR MISS, and the feedback names both commands")
    func dwIsNearMiss() throws {
        let drills = try focusedDrills("grammar.delete-inner-word")
        #expect(!drills.isEmpty)

        for drill in drills {
            #expect(drill.commandKeys == "diw")
            let attempt = try #require(replay("dw", on: drill))
            #expect(!drill.succeeds(attempt))

            let judgement = drill.evaluate(attempt)
            guard case .nearMiss(let miss) = judgement else {
                Issue.record("expected a near miss for dw on \(drill.id), got \(judgement)")
                continue
            }
            #expect(miss.performedKeys == "dw")
            #expect(miss.targetKeys == "diw")
            #expect(miss.feedback.contains("`dw`"), "\(miss.feedback)")
            #expect(miss.feedback.contains("`diw`"), "\(miss.feedback)")
            #expect(miss.feedback.lowercased().contains("close"), "\(miss.feedback)")
            // The point of a near miss: it names the DIFFERENCE, not just "wrong".
            #expect(miss.feedback.contains("next word"), "\(miss.feedback)")
            #expect(miss.feedback.contains("whole word"), "\(miss.feedback)")
        }
    }

    @Test("target diw: an unrelated command is a plain (gentle) miss, not a near miss")
    func unrelatedCommandIsGenericMiss() throws {
        let drill = try #require(try focusedDrills("grammar.delete-inner-word").first)
        let attempt = try #require(replay("j", on: drill))
        let judgement = drill.evaluate(attempt)
        guard case .incorrect(let hint) = judgement else {
            Issue.record("expected a generic miss, got \(judgement)")
            return
        }
        #expect(hint.contains("`diw`"))
        #expect(hint.contains(drill.instruction))
        #expect(!hint.lowercased().contains("fail"))
    }

    // MARK: - Other confusion pairs

    @Test("target di\": da\" is recognized as taking the quote marks too")
    func quoteObjectNearMiss() throws {
        let drills = try focusedDrills("grammar.delete-inside-quotes")
        #expect(!drills.isEmpty)
        let drill = try #require(drills.first)
        let attempt = try #require(replay("da\"", on: drill))
        guard case .nearMiss(let miss) = drill.evaluate(attempt) else {
            Issue.record("expected a near miss for da\"")
            return
        }
        #expect(miss.performedKeys == "da\"")
        #expect(miss.feedback.contains("quote"))
    }

    @Test("target dd: x is recognized as only removing one character")
    func deleteLineNearMiss() throws {
        let drill = try #require(try focusedDrills("action.delete-line").first)
        let attempt = try #require(replay("x", on: drill))
        guard case .nearMiss(let miss) = drill.evaluate(attempt) else {
            Issue.record("expected a near miss for x on a dd drill")
            return
        }
        #expect(miss.performedKeys == "x")
        #expect(miss.feedback.contains("`dd`"))
    }

    // MARK: - Predicate rules

    @Test("a batch with no events is never judged (partial input is silence, not a mistake)")
    func noEventsIsNotAnAttempt() throws {
        let drill = try #require(try focusedDrills("grammar.delete-inner-word").first)
        let state = DrillState(
            text: drill.documentText, cursor: drill.start, mode: .normal, register: nil
        )
        let attempt = DrillAttempt(events: [], before: state, after: state)
        #expect(!drill.succeeds(attempt))
        #expect(drill.nearMiss(for: attempt) == nil)
    }

    @Test("category is load-bearing: the same end state from the wrong class is not success")
    func categoryDiscriminates() throws {
        let drill = try #require(try focusedDrills("grammar.delete-inner-word").first)
        #expect(drill.goal.category == .fullGrammar)

        // Same text/cursor/mode/register as the goal, but emitted as an
        // operator+motion (what `dw` is) — must not pass.
        let after = DrillState(
            text: drill.goal.text, cursor: drill.goal.cursor,
            mode: drill.goal.mode, register: drill.goal.register
        )
        let attempt = DrillAttempt(
            events: [CommandEvent(verb: .delete, category: .operatorMotion)],
            before: after,
            after: after
        )
        #expect(!drill.succeeds(attempt))
    }
}
