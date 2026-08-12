import Foundation
import Testing
@testable import Vimkin

// TODO(U2 cross-check): once the VimEngine (U2) merges, add the DB↔engine
// drift test — every tier-1/2 record's `keys` sequence must be accepted by
// VimEngine. Deliberately not written here; it needs the engine.
//
// Local-toolchain note: on a bare CommandLineTools install (no full Xcode) the
// `_Testing_Foundation` cross-import overlay ships without its swiftmodule, so
// plain `swift test` fails with "no such module". Workaround:
//   swift test \
//     -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
//     -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
//     -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
//     -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
// Full-Xcode environments (including CI) run plain `swift test` unchanged.

@Suite("CommandDatabase schema validation", .tags(.integration))
struct CommandDatabaseSchemaTests {

    private func loadDatabase() throws -> CommandDatabase {
        try CommandDatabase.load()
    }

    @Test("every record decodes and required fields are non-empty")
    func requiredFieldsNonEmpty() throws {
        let db = try loadDatabase()
        #expect(!db.commands.isEmpty)
        for command in db.commands {
            #expect(!command.id.isEmpty, "empty id")
            #expect(!command.keys.isEmpty, "empty keys for \(command.id)")
            #expect(!command.title.isEmpty, "empty title for \(command.id)")
            #expect(!command.description.isEmpty, "empty description for \(command.id)")
            #expect(!command.synonyms.isEmpty, "no synonyms for \(command.id)")
            #expect(
                command.synonyms.allSatisfy { !$0.isEmpty },
                "blank synonym in \(command.id)"
            )
        }
    }

    @Test("ids are unique")
    func idsUnique() throws {
        let db = try loadDatabase()
        let ids = db.commands.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids present")
    }

    @Test("keys are unique among engine-supported records within a mode")
    func keysUniquePerModeAmongEngineSupported() throws {
        let db = try loadDatabase()
        let supported = db.commands(engineSupported: true)
        let grouped = Dictionary(grouping: supported, by: \.mode)
        for (mode, commands) in grouped {
            let keys = commands.map(\.keys)
            #expect(
                Set(keys).count == keys.count,
                "duplicate keys among engine-supported records in mode \(mode)"
            )
        }
    }

    @Test("tiers are contiguous 1 through 5")
    func tiersContiguous() throws {
        let db = try loadDatabase()
        let tiers = Set(db.commands.map(\.tier))
        #expect(tiers == Set(1...5), "tiers present: \(tiers.sorted())")
    }

    @Test("every tier has at least one lesson, starting at lesson 1")
    func everyTierHasLessons() throws {
        let db = try loadDatabase()
        for tier in 1...5 {
            let lessons = db.commands(tier: tier).map(\.lesson)
            #expect(!lessons.isEmpty, "tier \(tier) has no records")
            #expect(lessons.min() == 1, "tier \(tier) lessons do not start at 1")
            #expect(lessons.allSatisfy { $0 >= 1 }, "tier \(tier) has a lesson below 1")
        }
    }

    @Test("engine-supported set is exactly tiers 1-4")
    func engineSupportSplit() throws {
        let db = try loadDatabase()
        for command in db.commands {
            if command.tier == 5 {
                #expect(!command.engineSupported, "\(command.id) is tier 5 but engineSupported")
            } else {
                #expect(command.engineSupported, "\(command.id) is tier \(command.tier) but not engineSupported")
            }
        }
    }
}

@Suite("CommandDatabase lookup and search", .tags(.integration))
struct CommandDatabaseLookupTests {

    private func loadDatabase() throws -> CommandDatabase {
        try CommandDatabase.load()
    }

    @Test("lookup by id")
    func lookupById() throws {
        let db = try loadDatabase()
        let record = db.command(id: "motion.word-forward")
        #expect(record?.keys == "w")
        #expect(record?.commandClass == .motion)
        #expect(db.command(id: "does.not-exist") == nil)
    }

    @Test("filter by tier, class, and engine support")
    func filters() throws {
        let db = try loadDatabase()
        #expect(!db.commands(tier: 1).isEmpty)
        #expect(!db.commands(class: .textObject).isEmpty)
        #expect(db.commands(class: .operator).map(\.keys).sorted() == ["c", "d", "y"])
        #expect(!db.commands(engineSupported: false).isEmpty)
        let total = db.commands(engineSupported: true).count + db.commands(engineSupported: false).count
        #expect(total == db.commands.count)
    }

    @Test("synonym search returns di\" as top result for 'delete inside quotes'")
    func synonymSearchDeleteInsideQuotes() throws {
        let db = try loadDatabase()
        let results = db.search("delete inside quotes")
        #expect(!results.isEmpty)
        #expect(results.first?.id == "grammar.delete-inside-quotes")
        #expect(results.first?.keys == "di\"")
    }

    @Test("search is case-insensitive and tolerates extra whitespace")
    func searchNormalization() throws {
        let db = try loadDatabase()
        #expect(db.search("  DELETE INSIDE QUOTES ").first?.keys == "di\"")
        #expect(db.search("") .isEmpty)
        #expect(db.search("   ").isEmpty)
    }

    @Test("literal keys lookup ranks the exact command first")
    func literalKeysSearch() throws {
        let db = try loadDatabase()
        #expect(db.search("dd").first?.id == "action.delete-line")
        #expect(db.search("gg").first?.id == "motion.file-top")
    }

    @Test("plain-English phrasings surface sensible commands")
    func plainEnglishSearch() throws {
        let db = try loadDatabase()
        #expect(db.search("save the file").first?.id == "cmd.write")
        #expect(db.search("copy the line").first?.id == "action.yank-line")
        #expect(db.search("undo").first?.id == "action.undo")
    }
}
