import Foundation
import Testing
@testable import Vimkin

// The complaint this suite exists to prevent recurring: "a lot of instructions
// you provide for practice and adventure and lessons are very confusing."
//
// It checks the SHIPPED content — every lesson step, every drill template,
// every World 1 level — against the floor a beginner needs:
//
//   • a lesson step must NAME the key it wants, in a code span;
//   • a drill must have keys that a reveal affordance can show;
//   • a level must produce an objective that says what to do;
//   • and no user-facing string may leak a raw `namespace.command-id`.

/// The backticked spans in a piece of instruction copy.
private func codeSpans(_ text: String) -> [String] {
    let parts = text.split(separator: "`", omittingEmptySubsequences: false)
    return parts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map { String($0.element) }
}

/// Canonical keys with control characters dropped — `:w\n` is typed as `:w`
/// plus Return, and the instruction names it that way.
private func printableKeys(_ keys: String) -> String {
    String(keys.filter { !$0.unicodeScalars.contains { scalar in scalar.value < 0x20 } })
}

/// Looks like `action.insert-line-end` — a developer identifier, not English.
private func looksLikeACommandID(_ text: String) -> Bool {
    text.split(separator: " ").contains { word in
        let parts = word.split(separator: ".")
        guard parts.count == 2, let tail = parts.last else { return false }
        return ["motion", "action", "grammar"].contains(String(parts[0]))
            && tail.allSatisfy { $0.isLowercase || $0 == "-" }
    }
}

@Suite("Shipped instructions name what to press", .tags(.integration))
struct InstructionClarityContentTests {

    // MARK: - Lessons

    @Test("every lesson step has an instruction and a hint")
    func lessonStepsAreWritten() throws {
        let database = try LessonDatabase.load()
        #expect(!database.lessons.isEmpty)
        for lesson in database.lessons {
            #expect(!lesson.steps.isEmpty, "\(lesson.id) has no steps")
            for step in lesson.steps {
                #expect(!step.instruction.isEmpty, "\(step.id) has no instruction")
                #expect(!step.canonicalKeys.isEmpty, "\(step.id) has no canonical keys")
            }
        }
    }

    @Test("every lesson step names its key inside a code span")
    func lessonStepsNameTheirKeys() throws {
        let database = try LessonDatabase.load()
        for lesson in database.lessons {
            for step in lesson.steps {
                let spans = codeSpans(step.instruction)
                #expect(!spans.isEmpty, "\(step.id): \"\(step.instruction)\" names no key at all")

                let wanted = printableKeys(step.canonicalKeys)
                if wanted.isEmpty {
                    // The only such key is `Esc`, and it must be named by name.
                    #expect(
                        spans.contains("Esc"),
                        "\(step.id) drills Esc without naming it"
                    )
                    continue
                }
                let named = Set(spans.joined())
                for character in wanted where !character.isWhitespace {
                    #expect(
                        named.contains(character),
                        "\(step.id): \"\(step.instruction)\" never shows `\(character)`"
                    )
                }
            }
        }
    }

    @Test("a lesson's outcome preview does not disagree with its own title")
    func outcomePreviewCaptionsAgreeWithTheirDoors() throws {
        // "Five doors into Insert" shipped with a caption reading "six doors,
        // six landing spots" over six key-caps. A learner counts.
        let database = try LessonDatabase.load()
        let spelled = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7]
        for lesson in database.lessons {
            guard let caption = database.preview(lessonID: lesson.id)?.caption?.lowercased()
            else { continue }
            let claimed = spelled.first { caption.hasPrefix($0.key + " ") }?.value
            guard let claimed else { continue }
            let titleClaim = spelled.first { lesson.title.lowercased().hasPrefix($0.key + " ") }?.value
            if let titleClaim {
                #expect(
                    claimed == titleClaim,
                    "\(lesson.id): the title says \(titleClaim) and the caption says \(claimed)"
                )
            }
        }
    }

    // MARK: - Drills

    @Test("every drill template has keys a reveal can show and a phrase to read")
    func drillTemplatesAreWritten() {
        #expect(!DrillCatalog.templates.isEmpty)
        for template in DrillCatalog.templates {
            #expect(!template.keys.isEmpty, "\(template.commandID) has no keys")
            #expect(!template.phrase.isEmpty, "\(template.commandID) has no phrase")
            #expect(!template.note.isEmpty, "\(template.commandID) has no near-miss note")
            #expect(
                template.phrase.count > 12,
                "\(template.commandID)'s phrase is too terse to act on"
            )
        }
    }

    @Test("a drill never leaks a raw command id at the learner")
    func drillCopyIsEnglish() {
        for template in DrillCatalog.templates {
            #expect(!looksLikeACommandID(template.phrase), "\(template.commandID) leaks an id")
            #expect(!looksLikeACommandID(template.note), "\(template.commandID) leaks an id")
            for confusable in template.confusables {
                #expect(!looksLikeACommandID(confusable.note), "\(template.commandID) leaks an id")
            }
        }
    }

    @Test("every drillable command has a human title to show instead of its id")
    func everyDrillableCommandHasATitle() throws {
        // The dojo's end-of-set panel printed `action.insert-line-end` at the
        // learner. It now looks the title up; this proves there is always one.
        let database = try CommandDatabase.load()
        for template in DrillCatalog.templates {
            let command = try #require(
                database.command(id: template.commandID),
                "\(template.commandID) is not in the command database"
            )
            let title = command.title
            #expect(!title.isEmpty, "\(template.commandID) has no title")
        }
    }

    // MARK: - Levels

    @Test("every World 1 level states an objective in plain words")
    func everyLevelHasAnObjective() throws {
        let world = try LevelDatabase.loadWorld1()
        #expect(!world.levels.isEmpty)
        for level in world.levels {
            let objective = LevelBriefing.objective(for: level)
            #expect(!objective.isEmpty, "\(level.id) has no objective")
            #expect(!looksLikeACommandID(objective))
            #expect(
                objective.lowercased().contains("vimkin"),
                "\(level.id)'s objective never mentions the thing you are rescuing"
            )
            #expect(LevelBriefing.parNote(for: level).contains("\(level.par)"))
        }
    }

    @Test("a level whose rules differ from the rest says so out loud")
    func unusualLevelsCarryExtraObjectives() throws {
        let world = try LevelDatabase.loadWorld1()
        for level in world.levels {
            let unusual = level.vimkins.contains { !$0.condition.isReach }
                || !level.extraGoals.isEmpty
            let extras = LevelBriefing.extraObjectives(for: level)
            #expect(
                unusual == !extras.isEmpty,
                "\(level.id): extra rules and extra explanation must go together"
            )
        }
    }

    @Test("the boss level explains both of the rules it changes")
    func bossLevelExplainsItself() throws {
        // World 1's last page is the only one that (a) frees a Vimkin by having
        // a word typed back in and (b) carries a completion goal that is not
        // drawn anywhere. Played cold, the HUD reads 4/4 and nothing happens.
        let world = try LevelDatabase.loadWorld1()
        let boss = try #require(world.levels.last)
        let extras = LevelBriefing.extraObjectives(for: boss)
        #expect(extras.count >= 2, "the boss changes two rules and must explain both")
        let remaining = LevelBriefing.remaining(
            for: boss, rescued: boss.vimkins.count, isComplete: false
        )
        #expect(remaining != nil, "the boss must say what is left when every Vimkin is free")
    }
}
