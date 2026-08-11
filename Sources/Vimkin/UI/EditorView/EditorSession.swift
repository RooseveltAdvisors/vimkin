// EditorSession.swift — observable state plumbing between VimEngine (a value-type
// state machine) and SwiftUI. Owns the engine struct, mutates it via feed(_:),
// and publishes emitted CommandEvents to an optional closure for downstream
// consumers (drills, game scoring, juice).

import Observation

@Observable
public final class EditorSession {
    public private(set) var engine: VimEngine

    /// Name of the document being edited (drives syntax tint by extension).
    public let documentName: String?

    /// Invoked after every feed that produced at least one CommandEvent.
    @ObservationIgnored
    public var onEvents: (([CommandEvent]) -> Void)?

    public init(text: String, documentName: String? = nil) {
        self.engine = VimEngine(text: text)
        self.documentName = documentName
    }

    public convenience init(document: CorpusDocument) {
        self.init(text: document.contents, documentName: document.name)
    }

    // MARK: - Input

    @discardableResult
    public func feed(_ key: KeyInput) -> [CommandEvent] {
        let events = engine.feed(key)
        if !events.isEmpty { onEvents?(events) }
        return events
    }

    /// Convenience mirroring `VimEngine.feed(keys:)` ("\u{1B}" = Esc, "\n"/"\r" = Enter).
    @discardableResult
    public func feed(keys: String) -> [CommandEvent] {
        var events: [CommandEvent] = []
        for c in keys {
            switch c {
            case "\u{1B}": events += feed(.escape)
            case "\n", "\r": events += feed(.enter)
            default: events += feed(.char(c))
            }
        }
        return events
    }

    // MARK: - Read-through state

    public var buffer: TextBuffer { engine.buffer }
    public var cursor: Position { engine.cursor }
    public var mode: Mode { engine.mode }
    public var commandLine: String { engine.commandLine }

    /// The charwise visual selection (inclusive both ends), or nil outside visual mode.
    /// Reads the engine's internal anchor — same-module access, Engine unmodified.
    public var selection: ClosedRange<Position>? {
        guard engine.mode == .visual, let anchor = engine.visualAnchor else { return nil }
        return min(anchor, engine.cursor) ... max(anchor, engine.cursor)
    }

    /// Language for syntax tinting, derived from the document name's extension.
    public var language: SyntaxTint.Language {
        guard let name = documentName, let dot = name.lastIndex(of: ".") else { return .plain }
        return SyntaxTint.Language(fileExtension: String(name[name.index(after: dot)...]))
    }
}
