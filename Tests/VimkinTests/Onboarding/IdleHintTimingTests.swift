import Foundation
import Testing
@testable import Vimkin

// All the idle-hint rules live in a pure value with an injected clock, so the
// timing can be asserted exactly instead of waited out.

@Suite("The idle hint waits, offers, and gets out of the way", .tags(.unit))
struct IdleHintTimingTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("nothing is offered before the delay is up")
    func quietButNotQuietEnough() {
        let timer = IdleHintTimer(delay: 8, start: start)
        #expect(!timer.isDue(at: start))
        #expect(!timer.isDue(at: start.addingTimeInterval(7.9)))
    }

    @Test("the hint is due exactly at the delay, and stays due")
    func dueOnTheBoundary() {
        let timer = IdleHintTimer(delay: 8, start: start)
        #expect(timer.isDue(at: start.addingTimeInterval(8)))
        #expect(timer.isDue(at: start.addingTimeInterval(60)))
    }

    @Test("the default delay is eight seconds")
    func defaultDelayIsEightSeconds() {
        #expect(IdleHintTimer.defaultDelay == 8)
        let timer = IdleHintTimer(start: start)
        #expect(!timer.isDue(at: start.addingTimeInterval(7.5)))
        #expect(timer.isDue(at: start.addingTimeInterval(8.5)))
    }

    @Test("pressing a key restarts the quiet spell")
    func activityResetsTheClock() {
        var timer = IdleHintTimer(delay: 8, start: start)
        #expect(timer.isDue(at: start.addingTimeInterval(9)))

        timer.noteActivity(at: start.addingTimeInterval(9))
        #expect(!timer.isDue(at: start.addingTimeInterval(10)))
        #expect(timer.isDue(at: start.addingTimeInterval(17)))
    }

    @Test("a new drill or step starts the quiet spell over")
    func restartResetsTheClock() {
        var timer = IdleHintTimer(delay: 8, start: start)
        #expect(timer.isDue(at: start.addingTimeInterval(20)))

        timer.restart(at: start.addingTimeInterval(20))
        #expect(!timer.isDue(at: start.addingTimeInterval(24)))
    }

    @Test("a dismissed hint stays away until the player does something")
    func dismissDisarmsUntilActivity() {
        var timer = IdleHintTimer(delay: 8, start: start)
        #expect(timer.isDue(at: start.addingTimeInterval(9)))

        timer.disarm()
        #expect(!timer.isDue(at: start.addingTimeInterval(30)))

        timer.noteActivity(at: start.addingTimeInterval(30))
        #expect(timer.isDue(at: start.addingTimeInterval(40)))
    }

    @Test("the phrasing names the key rather than nagging")
    func phrasingNamesTheKey() {
        let hint = IdleHintBar.forKeys("diw")
        #expect(hint.contains("`diw`"))
        #expect(hint.lowercased().contains("no rush"))
        #expect(!hint.contains("!"))
    }

    @Test("with no keys to name, the hint still says something kind")
    func phrasingSurvivesAnEmptyKeyString() {
        let hint = IdleHintBar.forKeys("")
        #expect(!hint.isEmpty)
        #expect(hint.lowercased().contains("no rush"))
    }

    @Test("the level form re-states the objective and lists the toolkit")
    func levelPhrasingCarriesObjectiveAndKeys() {
        let hint = IdleHintBar.forLevel(
            keys: ["h", "j", "k", "l"],
            objective: "Move the cursor onto each Vimkin to set it free."
        )
        #expect(hint.lowercased().contains("no rush"))
        #expect(hint.contains("vimkin".uppercased()) || hint.contains("Vimkin"))
        #expect(hint.contains("`h`"))
        #expect(hint.contains("`l`"))
    }
}
