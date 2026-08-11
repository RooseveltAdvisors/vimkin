import Foundation

/// A single Vim command record decoded from `Content/commands.json` — the
/// one-command-per-record database that drives lessons, drills, game unlocks,
/// and lookup search.
public struct VimCommand: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// The Vim mode the command is issued from (for `Esc`, the mode it leaves).
    public enum Mode: String, Codable, Sendable {
        case normal
        case visual
        case insert
        case cmdline
    }

    /// Curriculum classification of the record.
    public enum CommandClass: String, Codable, Sendable {
        case motion
        case `operator`
        case textObject = "text-object"
        case action
        case grammarExample = "grammar-example"
    }

    /// Stable slug, e.g. `"motion.word-forward"`.
    public let id: String
    /// The keystrokes, e.g. `"w"`, `"di\""`. Tier-5 lookup-only records may use
    /// placeholder notation like `"m{a-z}"`.
    public let keys: String
    public let mode: Mode
    public let commandClass: CommandClass
    /// Curriculum stage 1-5: survive, navigate, edit verbs, text-object grammar, advanced.
    public let tier: Int
    /// Lesson order within the tier.
    public let lesson: Int
    /// Short human name.
    public let title: String
    /// One clear sentence.
    public let description: String
    /// Plain-English phrasings a normal person would type when searching.
    public let synonyms: [String]
    /// True only for commands the v1 VimEngine accepts; false for lookup-only records.
    public let engineSupported: Bool

    enum CodingKeys: String, CodingKey {
        case id, keys, mode, tier, lesson, title, description, synonyms, engineSupported
        case commandClass = "class"
    }
}

/// Errors thrown while loading bundled content.
public enum ContentError: Error, Equatable {
    case missingResource(String)
}

extension Bundle {
    /// The bundle carrying Vimkin's `Content/` resources. (`Bundle.module` is
    /// internal, so it cannot appear in public default arguments directly.)
    public static var vimkinResources: Bundle { .module }
}

/// Loads and queries the command database.
public struct CommandDatabase: Sendable {
    public let commands: [VimCommand]

    public init(commands: [VimCommand]) {
        self.commands = commands
    }

    /// Decodes `Content/commands.json` from the given bundle (defaults to the module bundle).
    public static func load(from bundle: Bundle = .vimkinResources) throws -> CommandDatabase {
        guard let url = bundle.url(forResource: "commands", withExtension: "json", subdirectory: "Content") else {
            throw ContentError.missingResource("Content/commands.json")
        }
        let data = try Data(contentsOf: url)
        let commands = try JSONDecoder().decode([VimCommand].self, from: data)
        return CommandDatabase(commands: commands)
    }

    // MARK: - Lookup

    /// The record with the given id, if any.
    public func command(id: String) -> VimCommand? {
        commands.first { $0.id == id }
    }

    /// All records in the given curriculum tier, in file order.
    public func commands(tier: Int) -> [VimCommand] {
        commands.filter { $0.tier == tier }
    }

    /// All records of the given class, in file order.
    public func commands(class commandClass: VimCommand.CommandClass) -> [VimCommand] {
        commands.filter { $0.commandClass == commandClass }
    }

    /// All records filtered by engine support.
    public func commands(engineSupported: Bool) -> [VimCommand] {
        commands.filter { $0.engineSupported == engineSupported }
    }

    // MARK: - Synonym search

    /// Case-insensitive plain-English search over synonyms, title, description,
    /// and keys. Simple token scoring, no dependencies. Records with the best
    /// match come first; zero-score records are omitted.
    public func search(_ query: String, limit: Int = 10) -> [VimCommand] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return [] }
        let queryTokens = Self.tokenize(normalized)

        let scored: [(command: VimCommand, score: Int)] = commands.compactMap { command in
            let score = Self.score(command, query: normalized, queryTokens: queryTokens)
            return score > 0 ? (command, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.command.id < rhs.command.id
            }
            .prefix(limit)
            .map(\.command)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func score(_ command: VimCommand, query: String, queryTokens: [String]) -> Int {
        var score = 0

        // Literal keys lookup ("dd", "di\"") is the strongest signal.
        if command.keys.lowercased() == query {
            score += 120
        }

        let synonyms = command.synonyms.map { $0.lowercased() }
        if synonyms.contains(query) {
            score += 100
        } else if synonyms.contains(where: { $0.contains(query) }) {
            score += 60
        }

        if command.title.lowercased() == query {
            score += 80
        }

        let synonymTokens = Set(synonyms.flatMap(tokenize))
        let titleTokens = Set(tokenize(command.title))
        let descriptionTokens = Set(tokenize(command.description))
        for token in queryTokens {
            if synonymTokens.contains(token) { score += 10 }
            if titleTokens.contains(token) { score += 6 }
            if descriptionTokens.contains(token) { score += 2 }
        }

        return score
    }
}
