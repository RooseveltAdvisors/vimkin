import Foundation

/// One practice document from `Content/corpus/` — the realistic Markdown,
/// YAML, and JSON files that drills and game levels navigate.
public struct CorpusDocument: Identifiable, Equatable, Sendable {
    /// File name including extension, e.g. `"meeting-notes.md"`.
    public let name: String
    /// Full text of the document.
    public let contents: String

    public var id: String { name }

    /// The file extension, e.g. `"md"`, `"yaml"`, `"json"`.
    public var fileExtension: String {
        (name as NSString).pathExtension
    }

    public init(name: String, contents: String) {
        self.name = name
        self.contents = contents
    }
}

/// Lists and loads the bundled practice corpus.
public enum Corpus {
    /// The canonical corpus, in curriculum order.
    public static let documentNames: [String] = [
        "meeting-notes.md",
        "weekly-journal.md",
        "project-readme.md",
        "app-config.yaml",
        "api-response.json",
        "recipe-collection.md",
    ]

    /// Loads every corpus document from the given bundle (defaults to the module bundle).
    public static func loadAll(from bundle: Bundle = .vimkinResources) throws -> [CorpusDocument] {
        try documentNames.map { try load(name: $0, from: bundle) }
    }

    /// Loads a single corpus document by file name, e.g. `"meeting-notes.md"`.
    public static func load(name: String, from bundle: Bundle = .vimkinResources) throws -> CorpusDocument {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext, subdirectory: "Content/corpus") else {
            throw ContentError.missingResource("Content/corpus/\(name)")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return CorpusDocument(name: name, contents: contents)
    }
}
