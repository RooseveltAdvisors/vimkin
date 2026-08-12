import Foundation
import Testing
@testable import Vimkin

/// The restricted YAML front-matter parser the level files are written in —
/// exercised on inline documents only, so it pins the grammar itself rather
/// than the shipped content. (The shipped World 1 files are validated against
/// this parser by `LevelLoaderTests` — integration tier.)
@Suite("Game: the restricted level-YAML parser", .tags(.unit))
struct LevelYAMLParserTests {

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
