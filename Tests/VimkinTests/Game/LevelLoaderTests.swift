import Foundation
import Testing
@testable import Vimkin

/// Schema gate for World 1. Authored content is data, and data drifts — these
/// tests are the thing that stops a level from silently referencing a command
/// the engine cannot run, or a Vimkin standing outside its own document.
@Suite("Game: World 1 level loader + schema")
struct LevelLoaderTests {

    @Test("all ten World 1 levels load and parse")
    func allLevelsParse() throws {
        let world = try world1()
        #expect(world.levels.count == 10)
    }

    @Test("level order is contiguous 1...10 and ids are unique")
    func ordersAreContiguous() throws {
        let world = try world1()
        #expect(world.levels.map(\.order) == Array(1...10))
        #expect(Set(world.levels.map(\.id)).count == world.levels.count)
    }

    @Test("every required front-matter field is present and non-empty")
    func requiredFieldsPresent() throws {
        for level in try world1().levels {
            #expect(!level.id.isEmpty)
            #expect(!level.title.isEmpty, "\(level.id) has no title")
            #expect(!level.intro.isEmpty, "\(level.id) has no story beat")
            #expect(!level.teaches.isEmpty, "\(level.id) does not say what it teaches")
            #expect(!level.document.isEmpty, "\(level.id) has no terrain")
            #expect(!level.solution.isEmpty, "\(level.id) has no canonical solution")
            #expect(level.par > 0, "\(level.id) has a non-positive par")
            #expect(!level.vimkins.isEmpty, "\(level.id) traps nobody")
        }
    }

    /// The drift guard the plan asks for: a level may only hand the player
    /// commands the database knows AND the engine can actually execute.
    @Test("every allowed command id exists in commands.json and is engineSupported")
    func allowedCommandsExistAndRun() throws {
        let database = try gameCommands()
        for level in try world1().levels {
            #expect(!level.allowedCommandIDs.isEmpty, "\(level.id) allows no commands")
            for id in level.allowedCommandIDs {
                let command = database.command(id: id)
                #expect(command != nil, "\(level.id): unknown command id `\(id)`")
                #expect(
                    command?.engineSupported == true,
                    "\(level.id): `\(id)` is not engineSupported — the level would be unplayable"
                )
            }
            #expect(
                Set(level.allowedCommandIDs).count == level.allowedCommandIDs.count,
                "\(level.id) lists a command twice"
            )
        }
    }

    @Test("World 1 only teaches curriculum tiers 1 and 2")
    func world1StaysInTierOneAndTwo() throws {
        let database = try gameCommands()
        for level in try world1().levels {
            for id in level.allowedCommandIDs {
                let tier = database.command(id: id)?.tier ?? 99
                #expect(tier <= 2, "\(level.id) allows tier-\(tier) command `\(id)`")
            }
        }
    }

    @Test("levels get harder: each level's toolkit contains the previous one's")
    func toolkitsAreCumulative() throws {
        let levels = try world1().levels
        for (previous, current) in zip(levels, levels.dropFirst()) {
            let lost = Set(previous.allowedCommandIDs).subtracting(current.allowedCommandIDs)
            #expect(
                lost.isEmpty,
                "\(current.id) takes back \(lost.sorted()) — progression should only add"
            )
        }
    }

    @Test("every Vimkin stands on a real position inside its own document")
    func vimkinsAreInsideTheDocument() throws {
        for level in try world1().levels {
            let buffer = TextBuffer(text: level.document)
            for vimkin in level.vimkins {
                #expect(
                    vimkin.position.line >= 0 && vimkin.position.line < buffer.lineCount,
                    "\(level.id): \(vimkin.id) is on line \(vimkin.position.line) of a \(buffer.lineCount)-line document"
                )
                guard vimkin.position.line < buffer.lineCount else { continue }
                let length = buffer.lineLength(vimkin.position.line)
                #expect(
                    vimkin.position.col >= 0 && vimkin.position.col <= max(0, length - 1),
                    "\(level.id): \(vimkin.id) at col \(vimkin.position.col) is off the end of a \(length)-character line"
                )
            }
            #expect(
                Set(level.vimkins.map(\.id)).count == level.vimkins.count,
                "\(level.id) has two Vimkins with the same name"
            )
        }
    }

    @Test("a `written` goal's text is absent at the start — otherwise it is free")
    func writtenGoalsStartUnsatisfied() throws {
        for level in try world1().levels {
            for condition in level.allConditions {
                if case .textPresent(let text) = condition {
                    #expect(
                        !level.document.contains(text),
                        "\(level.id): `\(text)` is already in the document"
                    )
                }
                if case .textRemoved(let text) = condition {
                    #expect(
                        level.document.contains(text),
                        "\(level.id): `\(text)` is not in the document to begin with"
                    )
                }
            }
        }
    }

    @Test("par leaves room for the canonical solution")
    func parIsAchievable() throws {
        for level in try world1().levels {
            #expect(
                level.par >= level.solution.count,
                "\(level.id): par \(level.par) < solution length \(level.solution.count)"
            )
        }
    }

    // MARK: - Parser unit tests

    private static let minimal = """
        ---
        id: sample
        title: Sample
        order: 3
        teaches: nothing at all
        intro: A worm walked in.
        allowed: [motion.left, motion.down]
        par: 9
        solution: jj
        vimkins:
          - { name: Pip, line: 1, col: 2, rescue: reach }
          - { name: Bo, line: 0, col: 0, rescue: removed, text: mess }
        goals:
          - { rescue: yanked, text: hello }
        ---
        first line
        second mess line
        """

    @Test("the restricted YAML subset parses into the level model")
    func parsesTheSubset() throws {
        let level = try LevelParser.parse(Self.minimal, fileName: "sample.md")
        #expect(level.id == "sample")
        #expect(level.order == 3)
        #expect(level.par == 9)
        #expect(level.allowedCommandIDs == ["motion.left", "motion.down"])
        #expect(level.vimkins.count == 2)
        #expect(level.vimkins[0].condition == .cursorReaches(Position(line: 1, col: 2)))
        #expect(level.vimkins[1].condition == .textRemoved("mess"))
        #expect(level.extraGoals == [.registerContains("hello")])
        #expect(level.document == "first line\nsecond mess line")
    }

    @Test("a document body keeps its blank lines but not its trailing newline")
    func bodyIsPreservedExactly() throws {
        let text = Self.minimal.replacingOccurrences(
            of: "first line\nsecond mess line",
            with: "one\n\nthree mess\n\n"
        )
        let level = try LevelParser.parse(text, fileName: "sample.md")
        #expect(level.document == "one\n\nthree mess")
    }

    @Test("quoted scalars decode escapes; unquoted scalars are verbatim")
    func scalarEscapes() {
        #expect(LevelParser.unquote("\"jj\\egg\"") == "jj\u{1B}gg")
        #expect(LevelParser.unquote("\"a\\nb\"") == "a\nb")
        #expect(LevelParser.unquote("plain: value, with comma") == "plain: value, with comma")
    }

    @Test("a comma inside a quoted flow value does not split the mapping")
    func quotedCommasSurvive() throws {
        let text = Self.minimal.replacingOccurrences(
            of: "{ name: Bo, line: 0, col: 0, rescue: removed, text: mess }",
            with: "{ name: Bo, line: 0, col: 0, rescue: removed, text: \"mess, all of it\" }"
        ).replacingOccurrences(of: "second mess line", with: "second mess, all of it line")
        let level = try LevelParser.parse(text, fileName: "sample.md")
        #expect(level.vimkins[1].condition == .textRemoved("mess, all of it"))
    }

    @Test("malformed level files fail loudly, naming the file")
    func malformedFilesThrow() {
        #expect(throws: LevelError.self) {
            try LevelParser.parse("no front matter here", fileName: "bad.md")
        }
        #expect(throws: LevelError.self) {
            try LevelParser.parse("---\nid: x\nbody", fileName: "bad.md")
        }
        #expect(throws: LevelError.self) {
            try LevelParser.parse(
                Self.minimal.replacingOccurrences(of: "par: 9\n", with: ""), fileName: "bad.md")
        }
        #expect(throws: LevelError.self) {
            try LevelParser.parse(
                Self.minimal.replacingOccurrences(of: "rescue: reach", with: "rescue: nonsense"),
                fileName: "bad.md")
        }
        #expect(throws: LevelError.self) {
            try LevelParser.parse(
                Self.minimal.replacingOccurrences(of: ", line: 1, col: 2", with: ""),
                fileName: "bad.md")
        }
        #expect(throws: LevelError.self) {
            try LevelParser.parse(
                Self.minimal.replacingOccurrences(of: "order: 3", with: "order: three"),
                fileName: "bad.md")
        }
    }
}
