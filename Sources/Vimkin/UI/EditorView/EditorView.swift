// EditorView.swift — the reusable document renderer (U4): a SwiftUI Canvas
// monospace glyph grid driven by VimEngine state via EditorSession, laid out by
// the shared BufferLayout geometry. A mode badge sits in the corner, visual-mode
// selection is highlighted, a command-line strip appears in `:` mode, and
// md/json/yaml get a light line-based syntax tint. Keyboard input arrives
// through KeyCaptureView.
//
// The cursor (U19) is NOT part of the static grid. It lives on its own
// `TimelineView(.animation)` canvas layered over the text, because it is the
// player's avatar and has to behave like a character rather than a rectangle:
//
//   travel   eased movement between cells with a motion trail whose length
//            scales with the size of the jump (`G` reads nothing like `l`)
//   landing  a squash on arrival that settles
//   rest     a slow glow breath
//   morph    block ⇄ bar ⇄ underline with a colour shift and an outward ring on
//            every mode change; leaving Insert snaps back with a tighter shock
//   ghosts   optional outcome previews — where OTHER keys would land — drawn
//            before the learner commits, fading out once they do
//   reward   a burst at the cursor when a practice surface says "that's it"
//
// All of the arithmetic lives in `CursorRender` (pure, no SwiftUI), so this file
// stays a "draw what that says" layer.

import SwiftUI

public struct EditorView: View {
    private let session: EditorSession
    private let filter: KeyFilter
    private let onBlocked: ((KeyInput, String) -> Void)?
    private let feedback: KeyFeedbackHub?
    private let ghosts: [OutcomeGhost]

    /// Scroll persisted across frames; scrollToReveal keeps the cursor visible.
    @State private var scroll = LayoutPoint(x: 0, y: 0)

    // Live cursor animation state.
    @State private var flight: CursorFlight?
    @State private var modeShift: ModeShift?
    @State private var selectionChangedAt: Date?
    /// Ghosts kept on screen while they fade out, plus when the fade began.
    @State private var fadingGhosts: [OutcomeGhost] = []
    @State private var ghostFadeStart: Date?

    public init(
        session: EditorSession,
        filter: @escaping (KeyInput) -> KeyDecision = { _ in .allow },
        onBlocked: ((KeyInput, String) -> Void)? = nil,
        feedback: KeyFeedbackHub? = nil,
        ghosts: [OutcomeGhost] = []
    ) {
        self.session = session
        self.filter = filter
        self.onBlocked = onBlocked
        self.feedback = feedback
        self.ghosts = ghosts
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
        KeyCaptureView(
            filter: filter,
            onBlocked: onBlocked,
            onKey: { key in
                session.feed(key)
                feedback?.observe(key, session: session)
            }
        ) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack {
                        Canvas { ctx, size in
                            drawDocument(in: ctx, viewport: size)
                        }
                        TimelineView(.animation) { timeline in
                            Canvas { ctx, size in
                                drawLive(in: &ctx, viewport: size, now: timeline.date)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .onChange(of: session.cursor) { old, new in
                        persistScroll(viewport: proxy.size)
                        flight = CursorFlight(from: old, to: new, start: .now)
                    }
                    .onChange(of: session.mode) { old, new in
                        modeShift = ModeShift(from: old, to: new, start: .now)
                    }
                    .onChange(of: session.selection) { _, _ in
                        selectionChangedAt = .now
                    }
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
        .onChange(of: ghosts) { old, new in
            if new.isEmpty, !old.isEmpty {
                fadingGhosts = old
                ghostFadeStart = .now
            } else {
                fadingGhosts = new
                ghostFadeStart = nil
            }
        }
        .onAppear { fadingGhosts = ghosts }
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

    // MARK: - Static document layer

    private func drawDocument(in ctx: GraphicsContext, viewport: CGSize) {
        let layout = revealedLayout(viewport: viewport)
        let buffer = session.buffer
        let language = session.language
        let lineRange = layout.visibleLineRange(lineCount: buffer.lineCount)

        for rect in selectionRects(layout: layout, buffer: buffer, lineRange: lineRange) {
            ctx.fill(Path(rect), with: .color(EditorTheme.selection))
        }

        for line in lineRange {
            drawLine(line, in: ctx, layout: layout, buffer: buffer, language: language)
        }
    }

    private func viewRect(_ r: LayoutRect, _ layout: BufferLayout) -> CGRect {
        CGRect(x: r.x - layout.scroll.x, y: r.y - layout.scroll.y, width: r.width, height: r.height)
    }

    /// The cell rect for a FRACTIONAL grid position (the cursor mid-flight).
    private func cellRect(line: Double, col: Double, layout: BufferLayout) -> CGRect {
        CGRect(
            x: col * layout.cellSize.width - layout.scroll.x,
            y: line * layout.cellSize.height - layout.scroll.y,
            width: layout.cellSize.width,
            height: layout.cellSize.height
        )
    }

    private func selectionRects(
        layout: BufferLayout, buffer: TextBuffer, lineRange: Range<Int>
    ) -> [CGRect] {
        guard let sel = session.selection else { return [] }
        var rects: [CGRect] = []
        for line in sel.lowerBound.line ... sel.upperBound.line where lineRange.contains(line) {
            let len = buffer.lineLength(line)
            let startCol = line == sel.lowerBound.line ? sel.lowerBound.col : 0
            let endCol = line == sel.upperBound.line ? sel.upperBound.col : max(len - 1, 0)
            guard endCol >= startCol else { continue }
            let first = layout.cellRect(line: line, col: startCol)
            let last = layout.cellRect(line: line, col: endCol)
            rects.append(viewRect(
                LayoutRect(x: first.x, y: first.y, width: last.maxX - first.x, height: first.height),
                layout
            ))
        }
        return rects
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

    // MARK: - Live (animated) layer

    private func drawLive(in ctx: inout GraphicsContext, viewport: CGSize, now: Date) {
        let layout = revealedLayout(viewport: viewport)
        drawSelectionPulse(in: ctx, layout: layout, now: now)
        drawGhosts(in: ctx, layout: layout, viewportWidth: viewport.width, now: now)
        drawCursor(in: &ctx, layout: layout, now: now)
        drawModeRing(in: ctx, layout: layout, now: now)
        drawReward(in: ctx, layout: layout, now: now)
    }

    /// A wash that brightens each time the visual selection grows, so the
    /// selection reads as something you are actively dragging out.
    private func drawSelectionPulse(in ctx: GraphicsContext, layout: BufferLayout, now: Date) {
        guard session.mode == .visual, let changed = selectionChangedAt else { return }
        let progress = CursorRender.clamp01(now.timeIntervalSince(changed) / 0.32)
        let strength = (1 - progress) * 0.30
        guard strength > 0.005 else { return }
        let lineRange = layout.visibleLineRange(lineCount: session.buffer.lineCount)
        for rect in selectionRects(layout: layout, buffer: session.buffer, lineRange: lineRange) {
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(EditorTheme.amber.opacity(strength))
            )
        }
    }

    // MARK: Ghost previews

    private func drawGhosts(
        in ctx: GraphicsContext, layout: BufferLayout, viewportWidth: Double, now: Date
    ) {
        guard !fadingGhosts.isEmpty else { return }
        var alpha = 1.0
        if let start = ghostFadeStart {
            alpha = 1 - CursorRender.clamp01(
                now.timeIntervalSince(start) / CursorRender.ghostFadeDuration
            )
            guard alpha > 0.01 else { return }
        }
        // A slow shared shimmer so the ghosts read as "possible", not "there".
        let shimmer = 0.62 + 0.22 * sin(now.timeIntervalSinceReferenceDate * 2.2)
        let cellHeight = layout.cellSize.height

        // 1. Resolve every ghost to a body rect.
        var marks: [(ghost: OutcomeGhost, body: CGRect, isSeam: Bool)] = []
        for ghost in fadingGhosts {
            switch ghost.anchor {
            case .cell(let position):
                marks.append((
                    ghost,
                    viewRect(layout.cellRect(line: position.line, col: position.col), layout),
                    false
                ))
            case .newLine(let above):
                // The line does not exist yet — draw the full-width seam it
                // would open on, so `o`/`O` read as "a whole new line appears
                // HERE" and their labels land clear of the cell ghosts.
                let seam = viewRect(layout.cellRect(line: above, col: 0), layout)
                marks.append((
                    ghost,
                    CGRect(
                        x: seam.minX, y: seam.minY - 2.5,
                        width: max(viewportWidth - seam.minX - 74, layout.cellSize.width * 10),
                        height: 6
                    ),
                    true
                ))
            }
        }

        // 2. Draw the marks themselves.
        for mark in marks {
            let tint = Color(hex: EditorTheme.badgeHex(for: mark.ghost.mode))
            let outline = Path(
                roundedRect: mark.body.insetBy(dx: -1.5, dy: -1.5),
                cornerRadius: mark.isSeam ? 3 : 4
            )
            ctx.fill(outline, with: .color(tint.opacity(alpha * 0.16)))
            ctx.stroke(
                outline,
                with: .color(tint.opacity(alpha * shimmer)),
                style: StrokeStyle(lineWidth: 1.7, dash: [3.5, 3])
            )
        }

        // 3. Lay the key labels out so they never cover the document, and never
        //    each other: cell ghosts get a chip one row ABOVE their cell (below,
        //    on the top line), seams get theirs out past the end of the seam.
        //    Chips sharing a row are spread apart, then joined to their mark by
        //    a leader — a plain "chip on the cell" collides the moment two doors
        //    land on neighbouring columns, which is exactly the common case.
        struct Chip {
            let label: String
            let tint: Color
            let anchorX: Double
            let mark: CGRect
            var x: Double
            let width: Double
            let rowY: Double
        }
        var chips: [Chip] = []
        for mark in marks {
            let label = KeyGlyph.label(forKeys: mark.ghost.keys)
            let width = 13.0 + 9.0 * Double(label.count)
            let tint = Color(hex: EditorTheme.badgeHex(for: mark.ghost.mode))
            if mark.isSeam {
                chips.append(Chip(
                    label: label, tint: tint, anchorX: mark.body.maxX,
                    mark: mark.body, x: mark.body.maxX + 12, width: width, rowY: mark.body.midY
                ))
            } else {
                // Centred on the row above the cell (below it, on the top line),
                // so a chip never lands on the glyphs it is pointing at.
                let above = mark.body.midY - cellHeight
                let rowY = above < 10 ? mark.body.midY + cellHeight : above
                chips.append(Chip(
                    label: label, tint: tint, anchorX: mark.body.midX,
                    mark: mark.body, x: mark.body.midX - width / 2, width: width, rowY: rowY
                ))
            }
        }
        // Declutter each row left-to-right.
        let rows = Dictionary(grouping: chips.indices) { (chips[$0].rowY * 2).rounded() }
        for indices in rows.values {
            var cursorX = -Double.infinity
            for index in indices.sorted(by: { chips[$0].x < chips[$1].x }) {
                chips[index].x = max(chips[index].x, cursorX)
                cursorX = chips[index].x + chips[index].width + 5
            }
        }

        for chip in chips {
            let rect = CGRect(x: chip.x, y: chip.rowY - 9, width: chip.width, height: 18)
            // Leader from the chip to the mark it names.
            var leader = Path()
            leader.move(to: CGPoint(x: rect.midX, y: rect.midY))
            leader.addLine(to: CGPoint(x: chip.anchorX, y: chip.mark.midY))
            ctx.stroke(
                leader,
                with: .color(chip.tint.opacity(alpha * 0.45)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(chip.tint.opacity(alpha * 0.95))
            )
            ctx.draw(
                Text(chip.label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(EditorTheme.background.opacity(alpha)),
                at: CGPoint(x: rect.midX, y: rect.midY),
                anchor: .center
            )
        }
    }

    // MARK: Cursor

    private func drawCursor(in ctx: inout GraphicsContext, layout: BufferLayout, now: Date) {
        let cursor = session.cursor

        // Where is the cursor right now, in fractional grid coordinates?
        var line = Double(cursor.line)
        var col = Double(cursor.col)
        var progress = 1.0
        var horizontal = true

        if let flight, flight.to == cursor {
            let elapsed = now.timeIntervalSince(flight.start)
            progress = CursorRender.clamp01(elapsed / max(flight.duration, 0.001))
            let eased = CursorRender.easeOutCubic(progress)
            line = Double(flight.from.line) + Double(flight.to.line - flight.from.line) * eased
            col = Double(flight.from.col) + Double(flight.to.col - flight.from.col) * eased
            horizontal = abs(flight.to.col - flight.from.col) >= abs(flight.to.line - flight.from.line)

            drawTrail(in: ctx, layout: layout, flight: flight, progress: progress)
        }

        // Shape + colour, mid-morph if a mode just changed.
        let cell = cellRect(line: line, col: col, layout: layout)
        var silhouette = CursorRender.silhouette(mode: session.mode, cell: cell)
        var tint = Color(hex: EditorTheme.badgeHex(for: session.mode))
        if let shift = modeShift, shift.to == session.mode {
            let t = CursorRender.clamp01(
                now.timeIntervalSince(shift.start) / CursorRender.morphDuration
            )
            silhouette = CursorRender.lerp(
                CursorRender.silhouette(mode: shift.from, cell: cell), silhouette, t
            )
            tint = EditorTheme.mix(
                EditorTheme.badgeHex(for: shift.from), EditorTheme.badgeHex(for: shift.to), t
            )
        }

        // Impact squash, once the flight has landed.
        if let flight, flight.to == cursor, progress >= 1, flight.cells > 0.5 {
            let sinceLanding = now.timeIntervalSince(flight.start) - flight.duration
            let landing = CursorRender.clamp01(sinceLanding / CursorRender.landingDuration)
            if landing < 1 {
                silhouette = CursorRender.squashed(silhouette, landing: landing, along: horizontal)
            }
        }

        // The resting breath — a soft halo that never stops entirely.
        let glow = CursorRender.restingGlow(at: now.timeIntervalSinceReferenceDate)
        let path = Path(roundedRect: silhouette, cornerRadius: 2.5)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.fill(
                Path(roundedRect: silhouette.insetBy(dx: -3, dy: -3), cornerRadius: 5),
                with: .color(tint.opacity(glow * 0.55))
            )
        }
        ctx.fill(path, with: .color(tint))

        // Repaint the glyph under a settled block cursor in background ink.
        let settled = progress >= 1 && modeMorphComplete(now: now)
        if settled, isBlockMode(session.mode), let c = session.buffer.char(at: cursor) {
            ctx.draw(
                Text(String(c)).font(Self.font).foregroundColor(EditorTheme.background),
                at: CGPoint(x: silhouette.minX, y: silhouette.midY),
                anchor: .leading
            )
        }
    }

    private func isBlockMode(_ mode: Mode) -> Bool {
        switch mode {
        case .normal, .visual, .commandLine: return true
        case .insert, .operatorPending: return false
        }
    }

    private func modeMorphComplete(now: Date) -> Bool {
        guard let shift = modeShift, shift.to == session.mode else { return true }
        return now.timeIntervalSince(shift.start) >= CursorRender.morphDuration
    }

    /// After-images along the path just travelled. Length scales with the jump.
    private func drawTrail(
        in ctx: GraphicsContext, layout: BufferLayout, flight: CursorFlight, progress: Double
    ) {
        let count = CursorRender.trailCount(cells: flight.cells)
        guard count > 0, progress < 1 else { return }
        let tint = Color(hex: EditorTheme.badgeHex(for: session.mode))

        for step in 1 ... count {
            let lag = Double(step) * 0.085
            let eased = CursorRender.easeOutCubic(progress - lag)
            guard eased > 0 else { continue }
            let line = Double(flight.from.line) + Double(flight.to.line - flight.from.line) * eased
            let col = Double(flight.from.col) + Double(flight.to.col - flight.from.col) * eased
            let rect = cellRect(line: line, col: col, layout: layout)
                .insetBy(dx: Double(step) * 0.7, dy: Double(step) * 0.9)
            let fade = (1 - Double(step) / Double(count + 1)) * (1 - progress) * 0.55
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(tint.opacity(fade))
            )
        }
    }

    // MARK: Mode ring

    /// The drama on a mode change: an outward ripple entering a mode, and a
    /// tighter double shock when Insert snaps shut.
    private func drawModeRing(in ctx: GraphicsContext, layout: BufferLayout, now: Date) {
        guard let shift = modeShift, shift.from != shift.to else { return }
        let elapsed = now.timeIntervalSince(shift.start)
        guard elapsed < CursorRender.ringDuration else { return }
        let cell = cellRect(
            line: Double(session.cursor.line), col: Double(session.cursor.col), layout: layout
        )
        let center = CGPoint(x: cell.midX, y: cell.midY)
        let tint = Color(hex: EditorTheme.badgeHex(for: shift.to))
        let rings = shift.isLeavingInsert ? 2 : 1
        let reach = shift.isEnteringInsert ? 52.0 : (shift.isLeavingInsert ? 34.0 : 40.0)

        for ring in 0 ..< rings {
            let offset = Double(ring) * 0.09
            let t = CursorRender.clamp01((elapsed - offset) / CursorRender.ringDuration)
            guard t > 0, t < 1 else { continue }
            let radius = 6 + reach * CursorRender.easeOutCubic(t)
            let alpha = (1 - t) * (shift.isEnteringInsert ? 0.85 : 0.6)
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(tint.opacity(alpha)),
                lineWidth: 2.6 * (1 - t) + 0.6
            )
        }
    }

    // MARK: Reward burst

    /// "That's it" — rendered where the learner is looking: at the cursor.
    private func drawReward(in ctx: GraphicsContext, layout: BufferLayout, now: Date) {
        guard let reward = feedback?.reward else { return }
        let elapsed = now.timeIntervalSince(reward.date)
        guard elapsed >= 0, elapsed < CursorRender.rewardDuration else { return }
        let t = CursorRender.clamp01(elapsed / CursorRender.rewardDuration)
        let spec = reward.tier.effect
        let cell = cellRect(
            line: Double(session.cursor.line), col: Double(session.cursor.col), layout: layout
        )
        let center = CGPoint(x: cell.midX, y: cell.midY)
        let tint = Color(hex: spec.tintHex)
        let travel = CursorRender.easeOutCubic(t)
        let fade = 1 - t

        // A core flash at the cursor itself — the eye is already there.
        let core = 6 + 26 * travel
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - core, y: center.y - core, width: core * 2, height: core * 2
                )),
                with: .color(tint.opacity(fade * 0.55))
            )
        }

        // Shockwave.
        let radius = 8 + (reward.tier == .burst ? 88.0 : 52.0) * travel
        ctx.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
            )),
            with: .color(tint.opacity(fade)),
            lineWidth: 5.5 * fade + 1
        )

        // Specks — deterministic fan, so a redraw never re-scrambles them.
        let count = max(spec.particleCount, 9)
        let phase = Double(reward.id % 97) / 97
        for index in 0 ..< count {
            let angle = (Double(index) / Double(count) + phase) * 2 * .pi
            let wobble = 0.7 + 0.55 * Double((index &* 7) % 5) / 4
            let distance = radius * 0.92 * wobble
            let size = (2.6 + 2.8 * wobble) * (0.35 + 0.65 * fade)
            let dot = CGRect(
                x: center.x + cos(angle) * distance - size,
                y: center.y + sin(angle) * distance - size,
                width: size * 2, height: size * 2
            )
            ctx.fill(Path(ellipseIn: dot), with: .color(tint.opacity(fade)))
        }
    }
}
