import Testing
@testable import Vimkin

@Suite("SyntaxTint: line-based classifier for md / json / yaml", .tags(.unit))
struct SyntaxTintTests {
    // MARK: - Markdown

    @Test func markdownHeaderLinesClassified() {
        let h1 = SyntaxTint.spans(for: "# Meeting Notes", language: .markdown)
        #expect(h1 == [SyntaxTint.Span(range: 0 ..< 15, kind: .header)])

        let h3 = SyntaxTint.spans(for: "### Action Items", language: .markdown)
        #expect(h3.count == 1)
        #expect(h3[0].kind == .header)
        #expect(h3[0].range == 0 ..< 16)
    }

    @Test func markdownNonHeadersNotClassifiedAsHeaders() {
        // No space after # → not a heading; plain prose → no spans.
        #expect(SyntaxTint.spans(for: "#hashtag", language: .markdown).isEmpty)
        #expect(SyntaxTint.spans(for: "plain prose line", language: .markdown).isEmpty)
        #expect(SyntaxTint.spans(for: "", language: .markdown).isEmpty)
        // 7 #s is not a heading level.
        #expect(SyntaxTint.spans(for: "####### too deep", language: .markdown).isEmpty)
    }

    @Test func markdownListBulletTinted() {
        let spans = SyntaxTint.spans(for: "  - item one", language: .markdown)
        #expect(spans == [SyntaxTint.Span(range: 2 ..< 3, kind: .key)])
    }

    // MARK: - JSON

    @Test func jsonKeysAndStringValuesClassified() {
        let line = #"  "name": "vimkin","#
        let spans = SyntaxTint.spans(for: line, language: .json)
        #expect(spans.count == 2)
        #expect(spans[0].kind == .key)
        #expect(spans[0].range == 2 ..< 8)     // "name" including quotes
        #expect(spans[1].kind == .string)
        #expect(spans[1].range == 10 ..< 18)   // "vimkin" including quotes
    }

    @Test func jsonKeyWithNonStringValueOnlyTintsKey() {
        let spans = SyntaxTint.spans(for: #"  "count": 42,"#, language: .json)
        #expect(spans.count == 1)
        #expect(spans[0].kind == .key)
    }

    @Test func jsonPlainPunctuationLinesHaveNoSpans() {
        #expect(SyntaxTint.spans(for: "  },", language: .json).isEmpty)
        #expect(SyntaxTint.spans(for: "[", language: .json).isEmpty)
    }

    // MARK: - YAML

    @Test func yamlKeysClassified() {
        let spans = SyntaxTint.spans(for: "  timeout: 30", language: .yaml)
        #expect(spans == [SyntaxTint.Span(range: 2 ..< 9, kind: .key)])
    }

    @Test func yamlListItemKeyClassified() {
        let spans = SyntaxTint.spans(for: "  - name: web", language: .yaml)
        #expect(spans == [SyntaxTint.Span(range: 4 ..< 8, kind: .key)])
    }

    @Test func yamlCommentsClassified() {
        let full = SyntaxTint.spans(for: "# top-level comment", language: .yaml)
        #expect(full == [SyntaxTint.Span(range: 0 ..< 19, kind: .comment)])

        let trailing = SyntaxTint.spans(for: "port: 8080  # dev only", language: .yaml)
        #expect(trailing.contains(SyntaxTint.Span(range: 0 ..< 4, kind: .key)))
        #expect(trailing.contains(SyntaxTint.Span(range: 12 ..< 22, kind: .comment)))
    }

    @Test func yamlQuotedStringValueClassified() {
        let spans = SyntaxTint.spans(for: #"greeting: "hello""#, language: .yaml)
        #expect(spans.contains(SyntaxTint.Span(range: 0 ..< 8, kind: .key)))
        #expect(spans.contains(SyntaxTint.Span(range: 10 ..< 17, kind: .string)))
    }

    // MARK: - Plain / language routing

    @Test func plainLanguageNeverTints() {
        #expect(SyntaxTint.spans(for: "# not a header here", language: .plain).isEmpty)
    }

    @Test func languageFromExtension() {
        #expect(SyntaxTint.Language(fileExtension: "md") == .markdown)
        #expect(SyntaxTint.Language(fileExtension: "markdown") == .markdown)
        #expect(SyntaxTint.Language(fileExtension: "json") == .json)
        #expect(SyntaxTint.Language(fileExtension: "yaml") == .yaml)
        #expect(SyntaxTint.Language(fileExtension: "yml") == .yaml)
        #expect(SyntaxTint.Language(fileExtension: "txt") == .plain)
        #expect(SyntaxTint.Language(fileExtension: "") == .plain)
    }
}
