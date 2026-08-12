import Testing
@testable import Vimkin

/// Tests for the hub's content model (U18).
///
/// The hub is data (`Hub.groups`) plus a renderer that adds nothing, so the
/// things that can actually break — a duplicated jump key, a status line that
/// says "1 skills", a nav order that disagrees with the drawn order — are all
/// provable here without a window.

@Suite("Hub: the home screen's content", .tags(.unit))
struct HubModelTests {

    // MARK: - Keys

    @Test("every hub entry has a unique jump key")
    func jumpKeysAreUnique() {
        let keys = Hub.entries(HubStatus()).map(\.key)
        #expect(Set(keys).count == keys.count, "duplicate jump key in \(keys)")
    }

    @Test("the jump keys are the ones the design specifies")
    func jumpKeysAreTheDesignedOnes() {
        let byVerb = Dictionary(
            uniqueKeysWithValues: Hub.entries(HubStatus()).map { ($0.verb, $0.key) }
        )
        #expect(byVerb[Hub.Verb.adventure] == "a")
        #expect(byVerb[Hub.Verb.daily] == "d")
        #expect(byVerb[Hub.Verb.lessons] == "l")
        #expect(byVerb[Hub.Verb.practice] == "p")
        #expect(byVerb[Hub.Verb.progress] == "g")
        #expect(byVerb[Hub.Verb.playground] == "y")
    }

    @Test("no jump key collides with the hub's own motion or chrome keys")
    func jumpKeysDoNotShadowMotions() {
        // `j`/`k` move, `q` quits, `?` helps. A destination key that stole one
        // of these would make the hub unnavigable.
        let reserved: Set<Character> = ["j", "k", "q", "?"]
        for entry in Hub.entries(HubStatus()) {
            #expect(!reserved.contains(entry.key), "\(entry.verb) binds reserved key \(entry.key)")
        }
    }

    // MARK: - Order

    @Test("the flat nav order is exactly the groups read top to bottom")
    func navOrderMatchesTheDrawnOrder() {
        let status = HubStatus()
        let flat = Hub.entries(status).map(\.verb)
        let drawn = Hub.groups(status).flatMap { $0.entries.map(\.verb) }
        // `j`/`k` walk `entries`, the view draws `groups`. If these ever differ
        // the highlight lands on a different card than the one ⏎ opens.
        #expect(flat == drawn)
        #expect(
            flat == [
                Hub.Verb.adventure, Hub.Verb.daily,
                Hub.Verb.lessons, Hub.Verb.practice,
                Hub.Verb.progress, Hub.Verb.playground,
            ]
        )
    }

    @Test("the groups are the four intent bands, in order")
    func groupsAreTheIntentBands() {
        #expect(Hub.groups(HubStatus()).map(\.name) == ["PLAY", "TRAIN", "YOU", "SANDBOX"])
    }

    @Test("Typing is absent until the surface exists, rather than stubbed")
    func typingIsOmittedNotStubbed() {
        // A card that opens nothing is worse than no card. When a Typing
        // surface lands, this test is the reminder to add it here.
        let verbs = Hub.entries(HubStatus()).map(\.verb)
        #expect(!verbs.contains("typing"))
    }

    // MARK: - Status wording

    @Test("Adventure reports cleared levels out of the world's total")
    func adventureStatus() {
        let s = HubStatus(levelsCleared: 3, levelCount: 10)
        #expect(entry(Hub.Verb.adventure, s).status == "World 1 · 3/10 levels")
    }

    @Test("Adventure does not print a bogus 0/0 before the world has loaded")
    func adventureStatusBeforeLoad() {
        #expect(entry(Hub.Verb.adventure, HubStatus()).status == "World 1 · the Notebook")
    }

    @Test("Daily Run distinguishes 'not played' from a score of zero")
    func dailyStatus() {
        #expect(entry(Hub.Verb.daily, HubStatus()).status == "not played today")
        // A zero score is a PLAYED run, and must not read as unplayed.
        #expect(entry(Hub.Verb.daily, HubStatus(todaysScore: 0)).status == "today: 0")
        #expect(entry(Hub.Verb.daily, HubStatus(todaysScore: 940)).status == "today: 940")
    }

    @Test("Lessons reports learned out of total")
    func lessonStatus() {
        let s = HubStatus(lessonsLearned: 7, lessonCount: 16)
        #expect(entry(Hub.Verb.lessons, s).status == "7/16 learned")
    }

    @Test("Practice pluralises, and nudges when nothing is unlocked yet")
    func practiceStatus() {
        #expect(entry(Hub.Verb.practice, HubStatus()).status == "nothing unlocked yet")
        #expect(entry(Hub.Verb.practice, HubStatus(skillsUnlocked: 1)).status == "1 skill unlocked")
        #expect(entry(Hub.Verb.practice, HubStatus(skillsUnlocked: 9)).status == "9 skills unlocked")
    }

    @Test("Progress reports the practice window the way the design words it")
    func progressStatus() {
        let s = HubStatus(practicedDays: 32, windowDays: 40)
        #expect(entry(Hub.Verb.progress, s).status == "32 of the last 40 days")
        #expect(entry(Hub.Verb.progress, HubStatus()).status == "no practice logged yet")
    }

    @Test("every card carries a title, a blurb and a status — never a blank line")
    func everyCardIsFullyPopulated() {
        for entry in Hub.entries(HubStatus(
            levelsCleared: 1, levelCount: 10, todaysScore: 100,
            lessonsLearned: 2, lessonCount: 16, skillsUnlocked: 3,
            practicedDays: 4, documentCount: 6
        )) {
            #expect(!entry.title.isEmpty, "\(entry.verb) has no title")
            #expect(!entry.blurb.isEmpty, "\(entry.verb) has no blurb")
            #expect(!entry.status.isEmpty, "\(entry.verb) has no status")
        }
    }

    // MARK: - Helper

    private func entry(_ verb: String, _ status: HubStatus) -> HubEntry {
        guard let found = Hub.entries(status).first(where: { $0.verb == verb }) else {
            Issue.record("no hub entry for verb \(verb)")
            return HubEntry(key: "?", verb: verb, title: "", blurb: "", status: "")
        }
        return found
    }
}
