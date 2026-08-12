import Foundation
import Testing
@testable import Vimkin

@Suite("Corpus loading", .tags(.integration))
struct CorpusTests {

    @Test("all six corpus documents load and are non-empty")
    func loadsAllSixDocuments() throws {
        let documents = try Corpus.loadAll()
        #expect(documents.count == 6)
        #expect(documents.map(\.name) == Corpus.documentNames)
        for document in documents {
            #expect(!document.contents.isEmpty, "\(document.name) is empty")
        }
    }

    @Test("expected file names and formats are present")
    func expectedNamesAndFormats() {
        #expect(Corpus.documentNames.count == 6)
        let extensions = Set(Corpus.documentNames.map { ($0 as NSString).pathExtension })
        #expect(extensions == ["md", "yaml", "json"])
    }

    @Test("each document is a realistic drill length (30-80 lines)")
    func realisticLength() throws {
        for document in try Corpus.loadAll() {
            let lines = lineCount(of: document.contents)
            #expect((30...80).contains(lines), "\(document.name) has \(lines) lines")
        }
    }

    @Test("loading a single document by name works; unknown names throw")
    func loadSingleDocument() throws {
        let doc = try Corpus.load(name: "app-config.yaml")
        #expect(doc.fileExtension == "yaml")
        #expect(doc.contents.contains("Quill"))
        #expect(throws: ContentError.missingResource("Content/corpus/nope.md")) {
            _ = try Corpus.load(name: "nope.md")
        }
    }

    @Test("the JSON corpus document is valid JSON")
    func jsonDocumentParses() throws {
        let doc = try Corpus.load(name: "api-response.json")
        let object = try JSONSerialization.jsonObject(with: Data(doc.contents.utf8))
        #expect(object is [String: Any])
    }

    /// Counts content lines, ignoring a single trailing newline.
    private func lineCount(of text: String) -> Int {
        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.count
    }
}
