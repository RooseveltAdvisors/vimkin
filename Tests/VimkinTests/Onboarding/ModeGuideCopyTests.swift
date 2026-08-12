import Foundation
import Testing
@testable import Vimkin

// The whole point of a first-run guide is that it answers three questions:
// what am I doing, what do I press, how do I know it worked. A guide that
// drifts back into atmosphere-only prose is the bug this suite exists to catch
// — it is exactly what every mode looked like before U21.

@Suite("Every mode guide answers all three questions", .tags(.unit))
struct ModeGuideCopyTests {

    @Test("every mode has a guide, and the guide knows its mode")
    func everyModeHasAGuide() {
        #expect(ModeGuide.all.count == GuideMode.allCases.count)
        for mode in GuideMode.allCases {
            #expect(ModeGuide.guide(for: mode).mode == mode)
        }
    }

    @Test("every guide carries a title and a blurb")
    func titlesAndBlurbsAreWritten() {
        for guide in ModeGuide.all {
            #expect(!guide.title.isEmpty, "\(guide.mode) has no title")
            #expect(guide.blurb.count > 40, "\(guide.mode)'s blurb is too thin to explain anything")
        }
    }

    @Test("every guide answers doing / pressing / knowing, in that order")
    func theThreeQuestionsAreAllPresent() {
        let expected = [ModeGuide.doingLabel, ModeGuide.pressingLabel, ModeGuide.knowingLabel]
        for guide in ModeGuide.all {
            #expect(guide.beats.map(\.label) == expected, "\(guide.mode) is missing a beat")
            for beat in guide.beats {
                #expect(beat.text.count > 30, "\(guide.mode)/\(beat.label) is too thin")
            }
        }
    }

    @Test("the 'what you press' beat actually names keys")
    func pressingBeatNamesKeys() throws {
        for guide in ModeGuide.all {
            let pressing = try #require(
                guide.beats.first { $0.label == ModeGuide.pressingLabel },
                "\(guide.mode) has no 'what you press' beat"
            )
            #expect(
                pressing.text.contains("`"),
                "\(guide.mode) tells you what to press without naming a single key"
            )
        }
    }

    @Test("guides use backticks and no other markup")
    func onlyBackticksAreUsed() {
        // `LessonText` renders backticks and nothing else; any `**bold**` or
        // `*emphasis*` would be printed literally on screen.
        for guide in ModeGuide.all {
            let all = ([guide.title, guide.blurb] + guide.beats.map(\.text)).joined(separator: " ")
            #expect(!all.contains("*"), "\(guide.mode) uses markup LessonText cannot render")
            #expect(all.filter { $0 == "`" }.count.isMultiple(of: 2), "\(guide.mode) has an unclosed code span")
        }
    }

    @Test("the adventure guide says what a Vimkin is and how one is freed")
    func adventureGuideExplainsTheGame() {
        // Jon's complaint, verbatim: "I don't know what game I'm playing here."
        // Nothing in the app said what a Vimkin was, or that MOVING onto one is
        // what frees it, or that `par` is a target rather than a limit.
        let text = ([ModeGuide.adventure.blurb] + ModeGuide.adventure.beats.map(\.text))
            .joined(separator: " ").lowercased()
        #expect(text.contains("vimkin"))
        #expect(text.contains("cursor"))
        #expect(text.contains("free"))
        #expect(text.contains("par"))
        #expect(text.contains("not a limit") || text.contains("never a limit"))
    }
}
