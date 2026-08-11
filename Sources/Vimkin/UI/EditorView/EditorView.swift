// EditorView.swift — the reusable document renderer (U4): a SwiftUI Canvas
// monospace glyph grid driven by VimEngine state via EditorSession, laid out by
// the shared BufferLayout geometry. Cursor style tracks mode (block / bar /
// underline), a mode badge sits in the corner, visual-mode selection is
// highlighted, a command-line strip appears in `:` mode, and md/json/yaml get a
// light line-based syntax tint. Keyboard input arrives through KeyCaptureView.

import SwiftUI

public struct EditorView: View {
    private let session: EditorSession
    private let filter: KeyFilter
    private let onBlocked: ((KeyInput, String) -> Void)?

    /// Scroll persisted across frames; scrollToReveal keeps the cursor visible.
    @State private var scroll = LayoutPoint(x: 0, y: 0)

    public init(
        session: EditorSession,
        filter: @escaping (KeyInput) -> KeyDecision = { _ in .allow },
        onBlocked: ((KeyInput, String) -> Void)? = nil
    ) {
        self.session = session
        self.filter = filter
        self.onBlocked = onBlocked
    }

    // MARK: - Font / cell metrics (single source for layout AND drawing)

    private static let nsFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let font = Font(nsFont as CTFont)

    static let cellSize: LayoutSize = {
        let advance = ("M" as NSString).size(withAttributes: [.font: nsFont]).width
        let height = (nsFont.ascender - nsFont.descender + nsFont.leading).rounded(.up) + 2
        return LayoutSize(width: Double(advance), height: Double(height))
    }()

    // MARK: - Body

    public var body: some View {
        KeyCaptureView(filter: filter, onBlocked: onBlocked, onKey: { session.feed($0) }) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    Canvas { ctx, size in
                        draw(in: ctx, viewport: size)
                    }
                    .onChange(of: session.cursor) { persistScroll(viewport: proxy.size) }
                    .onChange(of: proxy.size) { persistScroll(viewport: proxy.size) }
                    .onAppear { persistScroll(viewport: proxy.size) }
                }
                .padding(12)
                if session.mode == .commandLine {
                    commandStrip
                }
            }
            .background(EditorTheme.background)
            .overlay(alignment: .bottomTrailing) { modeBadge }
        }
    }

    private var modeBadge: some View {
        let mode = session.mode
        return Text(EditorTheme.badgeLabel(for: mode))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(EditorTheme.badgeColor(for: mode))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(EditorTheme.badgeColor(for: mode).opacity(0.16), in: Capsule())
            .padding(12)
            .allowsHitTesting(false)
    }

    private var commandStrip: some View {
        HStack(spacing: 0) {
            Text(":\(session.commandLine)")
                .font(Self.font)
                .foregroundStyle(EditorTheme.text)
            Rectangle()
                .fill(EditorTheme.cursor)
                .frame(width: Self.cellSize.width, height: Self.cellSize.height - 4)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(EditorTheme.text.opacity(0.06))
    }

    // MARK: - Scroll

    private func revealedLayout(viewport: CGSize) -> BufferLayout {
        var layout = BufferLayout(
            cellSize: Self.cellSize,
            viewportSize: LayoutSize(width: viewport.width, height: viewport.height),
            scroll: scroll
        )
        // Insert-mode cursor may sit at col == lineLength; cellRect handles it.
        layout.scrollToReveal(session.cursor)
        return layout
    }

    private func persistScroll(viewport: CGSize) {
        let revealed = revealedLayout(viewport: viewport).scroll
        if revealed != scroll { scroll = revealed }
    }

    // MARK: - Drawing

    private func draw(in ctx: GraphicsContext, viewport: CGSize) {
        let layout = revealedLayout(viewport: viewport)
        let buffer = session.buffer
        let language = session.language
        let lineRange = layout.visibleLineRange(lineCount: buffer.lineCount)

        drawSelection(in: ctx, layout: layout, buffer: buffer, lineRange: lineRange)

        for line in lineRange {
            drawLine(line, in: ctx, layout: layout, buffer: buffer, language: language)
        }

        drawCursor(in: ctx, layout: layout, buffer: buffer)
    }

    private func viewRect(_ r: LayoutRect, _ layout: BufferLayout) -> CGRect {
        CGRect(x: r.x - layout.scroll.x, y: r.y - layout.scroll.y, width: r.width, height: r.height)
    }

    private func drawSelection(
        in ctx: GraphicsContext, layout: BufferLayout, buffer: TextBuffer, lineRange: Range<Int>
    ) {
        guard let sel = session.selection else { return }
        for line in sel.lowerBound.line ... sel.upperBound.line where lineRange.contains(line) {
            let len = buffer.lineLength(line)
            let startCol = line == sel.lowerBound.line ? sel.lowerBound.col : 0
            let endCol = line == sel.upperBound.line ? sel.upperBound.col : max(len - 1, 0)
            guard endCol >= startCol else { continue }
            let first = layout.cellRect(line: line, col: startCol)
            let last = layout.cellRect(line: line, col: endCol)
            let rect = LayoutRect(
                x: first.x, y: first.y, width: last.maxX - first.x, height: first.height
            )
            ctx.fill(Path(viewRect(rect, layout)), with: .color(EditorTheme.selection))
        }
    }

    private func drawLine(
        _ line: Int, in ctx: GraphicsContext, layout: BufferLayout,
        buffer: TextBuffer, language: SyntaxTint.Language
    ) {
        let text = buffer.line(line)
        guard !text.isEmpty else { return }
        let chars = Array(text)
        let colRange = layout.visibleColRange(maxLineLength: chars.count)
        guard !colRange.isEmpty else { return }

        let spans = SyntaxTint.spans(for: text, language: language)
        func color(at col: Int) -> Color {
            if let span = spans.first(where: { $0.range.contains(col) }) {
                return EditorTheme.tintColor(span.kind)
            }
            return EditorTheme.text
        }

        let lineY = layout.cellRect(line: line, col: 0)
        let centerY = lineY.y + lineY.height / 2 - layout.scroll.y

        // Group visible columns into same-color runs; monospace advance == cell width.
        var runStart = colRange.lowerBound
        var runColor = color(at: runStart)
        var col = runStart + 1
        func flush(to end: Int) {
            let x = Double(runStart) * layout.cellSize.width - layout.scroll.x
            let run = String(chars[runStart ..< end])
            ctx.draw(
                Text(run).font(Self.font).foregroundColor(runColor),
                at: CGPoint(x: x, y: centerY),
                anchor: .leading
            )
        }
        while col < colRange.upperBound {
            let c = color(at: col)
            if c != runColor {
                flush(to: col)
                runStart = col
                runColor = c
            }
            col += 1
        }
        flush(to: colRange.upperBound)
    }

    private func drawCursor(in ctx: GraphicsContext, layout: BufferLayout, buffer: TextBuffer) {
        let cursor = session.cursor
        let rect = viewRect(layout.cellRect(line: cursor.line, col: cursor.col), layout)

        switch session.mode {
        case .insert:
            // Bar cursor; valid even at col == lineLength (one past line end).
            let bar = CGRect(x: rect.minX - 1, y: rect.minY, width: 2, height: rect.height)
            ctx.fill(Path(bar), with: .color(EditorTheme.cursor))
        case .operatorPending:
            let underline = CGRect(x: rect.minX, y: rect.maxY - 2.5, width: rect.width, height: 2.5)
            ctx.fill(Path(underline), with: .color(EditorTheme.cursor))
        case .normal, .visual, .commandLine:
            ctx.fill(Path(rect), with: .color(EditorTheme.cursor))
            if let c = buffer.char(at: cursor) {
                // Repaint the glyph under the block in background ink for contrast.
                ctx.draw(
                    Text(String(c)).font(Self.font).foregroundColor(EditorTheme.background),
                    at: CGPoint(x: rect.minX, y: rect.midY),
                    anchor: .leading
                )
            }
        }
    }
}
