// GameScene.swift — the scrolling 2D tile world (plan U13, rebuilt from U7).
//
// The level's document IS the map. `TerrainMap` decides what every buffer cell
// is; this file draws that map as a top-down tile world and points a camera at
// the player:
//
//   sea of ink       — blank lines and everything past a line's end, shimmering
//   parchment island — the page itself, with a torn-paper rim where it meets ink
//   letter tiles     — raised paper tiles carrying one dark glyph each
//   ruled paths      — notebook rules running under indented and list rows
//   signpost banners — `#` heading strips
//   margin wall      — graph-paper blocks and the red rule down the page's edge
//
// On top of the terrain walk the cursor-spirit (a glowing cyan block trailing
// afterimages) and the Vimkins (amber-bellied ink creatures ~2 tiles tall).
//
// Two structural rules this file obeys:
//
//  1. IT OWNS NO GAME RULES. It is handed a GameState after every key and
//     redraws. Decisions live in GameState, grid math in GameGeometry, terrain
//     classification in TerrainMap, camera policy in TileCamera.
//  2. IT BUILDS FEW NODES. Terrain is batched into one node per layer (a single
//     CGPath of many tiles), never one node per cell — a 60x30 world is ~50
//     nodes, not 1800.
//
// Art is optional: if `Content/tiles/*.png` is present the terrain layers are
// drawn from that tileset instead, and if it is absent the programmatic shapes
// below stand in, so a build with no generated art is still a complete game.

import AppKit
import CoreImage
import SpriteKit
import SwiftUI

public final class GameScene: SKScene {

    // MARK: - Tunables

    /// Chunky, near-square tiles: this is a tile world, not a text view.
    /// Defined in `GameGeometry` so the pure camera/terrain tests can share it.
    static var tile: LayoutSize { GameGeometry.worldTile }
    /// Glyph size. Decoupled from the tile via kerning (see `buildGlyphs`), so
    /// the letters sit centred ON their tiles instead of setting the grid.
    private static let glyphSize: CGFloat = 19
    /// Columns of graph-paper wall standing in the page's left margin.
    private static let marginColumns = 2
    private static let trailLength = 6
    /// Camera ease. Long enough to read as a follow, short enough to keep up
    /// with a player hammering `j`.
    private static let followDuration: TimeInterval = 0.12
    private static let tileDirectory = "Content/tiles"
    private static let marginWallTexture = "tile-margin-wall"

    // MARK: - Layers (z order runs sea → land → decor → glyphs → cast)

    private let seaLayer = SKNode()
    private let shadowLayer = SKNode()
    private let marginLayer = SKNode()
    private let landLayer = SKNode()
    private let decorLayer = SKNode()
    private let tileArtLayer = SKNode()
    private let rimLayer = SKNode()
    private let glyphLayer = SKNode()
    private let markerLayer = SKNode()
    private let vimkinLayer = SKNode()
    private let playerLayer = SKNode()

    private let cameraNode = SKCameraNode()

    private var vimkinNodes: [String: VimkinNode] = [:]
    private var trailNodes: [SKShapeNode] = []
    private var player: SKNode!
    private var playerGlow: SKShapeNode!

    private var geometry: GameGeometry
    private var terrain: TerrainMap
    private var state: GameState
    private var lastRenderedLines: [String] = []
    private static let spriteCache = SpriteCache()

    // MARK: - Init

    public init(state: GameState, size: CGSize) {
        self.state = state
        self.terrain = TerrainMap(lines: state.documentLines)
        self.geometry = GameGeometry.make(
            lines: state.documentLines,
            cellSize: Self.tile,
            viewportSize: LayoutSize(width: Double(size.width), height: Double(size.height))
        )
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = GameTheme.nsColor(GameTheme.inkNavy)

        for (index, layer) in [
            seaLayer, shadowLayer, marginLayer, landLayer, decorLayer,
            tileArtLayer, rimLayer, glyphLayer, markerLayer, vimkinLayer, playerLayer,
        ].enumerated() {
            // Wide spacing: a child's local zPosition accumulates onto its
            // layer's, so layers must never be able to interleave.
            layer.zPosition = CGFloat(index) * 10
            addChild(layer)
        }

        addChild(cameraNode)
        camera = cameraNode
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("GameScene is created in code") }

    public override func didMove(to view: SKView) {
        buildPlayer()
        rebuildWorld()
        refresh(animated: false)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // A short page is centred in whatever room the window leaves, so the
        // whole world moves when the window resizes — rebuild, don't nudge.
        geometry = Self.makeGeometry(lines: state.documentLines, size: size)
        guard player != nil else { return }
        rebuildWorld()
        refresh(animated: false)
    }

    private static func makeGeometry(lines: [String], size: CGSize) -> GameGeometry {
        GameGeometry.make(
            lines: lines,
            cellSize: tile,
            viewportSize: LayoutSize(width: Double(size.width), height: Double(size.height))
        )
    }

    // MARK: - State updates (called by GameView after every key)

    /// Applies a new state and animates the difference.
    public func apply(_ newState: GameState, step: GameStep?) {
        let textChanged = newState.documentLines != lastRenderedLines
        state = newState
        if textChanged {
            geometry = Self.makeGeometry(lines: state.documentLines, size: size)
            rebuildWorld()
        }
        refresh(animated: true)

        if let step, step.wasBlocked { shimmer() }
        for vimkin in step?.newlyRescued ?? [] { pop(vimkin) }
    }

    private func refresh(animated: Bool) {
        layoutVimkins()
        movePlayer(to: state.engine.cursor, animated: animated)
        moveCamera(animated: animated)
    }

    /// Rebuilds every static layer of the map. Called only when the DOCUMENT or
    /// the viewport changes — never per key.
    private func rebuildWorld() {
        terrain = TerrainMap(lines: state.documentLines)
        lastRenderedLines = state.documentLines
        for layer in [
            seaLayer, shadowLayer, marginLayer, landLayer,
            decorLayer, tileArtLayer, rimLayer, glyphLayer,
        ] {
            layer.removeAllChildren()
        }
        buildSea()
        buildIslandShadow()
        buildMarginWall()
        buildIslandBase()
        buildSteppingStones()
        buildRuledPaths()
        buildBanners()
        buildLetterTiles()
        buildTileArt()
        buildIslandRim()
        buildGlyphs()
        rebuildVimkins()
    }

    // MARK: - Geometry helpers

    private var tileW: CGFloat { CGFloat(Self.tile.width) }
    private var tileH: CGFloat { CGFloat(Self.tile.height) }

    /// The rect a cell occupies in scene space. Negative columns are legal —
    /// that is where the notebook margin lives.
    private func cellRect(line: Int, col: Int) -> CGRect {
        let point = geometry.scenePoint(line: line, col: col)
        return CGRect(x: point.x, y: point.y, width: tileW, height: tileH)
    }

    /// The rect a half-open run of columns occupies on one line.
    private func runRect(line: Int, columns: Range<Int>) -> CGRect {
        let first = cellRect(line: line, col: columns.lowerBound)
        return CGRect(
            x: first.minX, y: first.minY,
            width: tileW * CGFloat(columns.count), height: tileH
        )
    }

    /// Everything the camera is allowed to look at: the page plus its margin.
    private var worldRect: LayoutRect {
        let origin = geometry.scenePoint(line: 0, col: -Self.marginColumns)
        let bottom = geometry.scenePoint(line: max(0, terrain.rowCount - 1), col: 0)
        let columns = Double(terrain.columnCount + Self.marginColumns)
        return LayoutRect(
            x: origin.x,
            y: bottom.y,
            width: max(Self.tile.width, columns * Self.tile.width),
            height: max(Self.tile.height, Double(terrain.rowCount) * Self.tile.height)
        )
    }

    // MARK: - The sea of ink

    private func buildSea() {
        let world = worldRect
        buildGraphPaper(around: world)
        var wobble = Wobble(seed: 0x5EA_1_1_1)
        // Slow, faint drifting streaks: enough motion that the void reads as a
        // living sea, never enough to compete with the page.
        for _ in 0..<20 {
            let width = 90 + wobble.next() * 260
            let node = SKShapeNode(
                rect: CGRect(x: -width / 2, y: -1.6, width: width, height: 3.2),
                cornerRadius: 1.6
            )
            node.fillColor = GameTheme.nsColor(GameTheme.seaShimmer)
            node.strokeColor = .clear
            node.alpha = 0.16 + wobble.next() * 0.14
            node.position = CGPoint(
                x: world.x - 260 + wobble.next() * (world.width + 520),
                y: world.y - 220 + wobble.next() * (world.height + 440)
            )
            let drift = 26 + wobble.next() * 40
            let duration = 5.5 + wobble.next() * 6
            node.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: drift, y: 0, duration: duration),
                    .fadeAlpha(to: 0.06, duration: duration),
                ]),
                .group([
                    .moveBy(x: -drift, y: 0, duration: duration),
                    .fadeAlpha(to: 0.28, duration: duration),
                ]),
            ])))
            seaLayer.addChild(node)
        }
    }

    /// The whole world sits on graph paper. Drawn very faintly across the sea
    /// so the void reads as the rest of the notebook page rather than as dead
    /// space — and so the grid the player moves on is legible even off-island.
    private func buildGraphPaper(around world: LayoutRect) {
        let bleed: CGFloat = 900
        let minX = CGFloat(world.x) - bleed
        let maxX = CGFloat(world.maxX) + bleed
        let minY = CGFloat(world.y) - bleed
        let maxY = CGFloat(world.maxY) + bleed
        let origin = cellRect(line: 0, col: 0)
        // Two weights, like real graph paper: a fine cell grid and a heavier
        // rule every fifth line.
        let fine = CGMutablePath()
        let major = CGMutablePath()
        var column = -Int((((origin.minX - minX) / tileW).rounded(.up)))
        var x = origin.minX + CGFloat(column) * tileW
        while x <= maxX {
            let path = column % 5 == 0 ? major : fine
            path.move(to: CGPoint(x: x, y: minY))
            path.addLine(to: CGPoint(x: x, y: maxY))
            x += tileW
            column += 1
        }
        var row = -Int((((origin.minY - minY) / tileH).rounded(.up)))
        var y = origin.minY + CGFloat(row) * tileH
        while y <= maxY {
            let path = row % 5 == 0 ? major : fine
            path.move(to: CGPoint(x: minX, y: y))
            path.addLine(to: CGPoint(x: maxX, y: y))
            y += tileH
            row += 1
        }
        for (path, width, alpha) in [(fine, 0.7, 0.26), (major, 1.2, 0.42)] {
            let grid = SKShapeNode(path: path)
            grid.strokeColor = GameTheme.nsColor(GameTheme.marginGrid)
            grid.lineWidth = width
            grid.alpha = alpha
            grid.fillColor = .clear
            grid.zPosition = -0.1
            seaLayer.addChild(grid)
        }
    }

    // MARK: - The island

    /// A soft drop shadow under the page, so parchment reads as floating ON ink
    /// rather than being a differently-coloured region of it.
    private func buildIslandShadow() {
        let path = CGMutablePath()
        for line in 0..<terrain.rowCount {
            guard let span = terrain.landSpan(line: line) else { continue }
            path.addRect(runRect(line: line, columns: span).insetBy(dx: -3, dy: -3))
        }
        guard !path.isEmpty else { return }
        let shadow = SKShapeNode(path: path)
        shadow.fillColor = GameTheme.nsColor(GameTheme.tileShadow)
        shadow.strokeColor = .clear
        shadow.alpha = 0.75
        shadow.position = CGPoint(x: 4, y: -6)

        let blur = SKEffectNode()
        blur.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 7.0])
        blur.shouldRasterize = true
        blur.addChild(shadow)
        shadowLayer.addChild(blur)
    }

    /// The sheet itself: one unbroken rect per line, so a ragged line end reads
    /// as a torn edge instead of a gap between tiles.
    private func buildIslandBase() {
        let path = CGMutablePath()
        for line in 0..<terrain.rowCount {
            guard let span = terrain.landSpan(line: line) else { continue }
            path.addRect(runRect(line: line, columns: span))
        }
        guard !path.isEmpty else { return }
        let node = SKShapeNode(path: path)
        node.fillColor = GameTheme.nsColor(GameTheme.groundTile)
        node.strokeColor = .clear
        landLayer.addChild(node)
    }

    /// A blank line is open water — but the cursor can still stand on it, so
    /// every blank row gets a stepping stone at column 0 to stand on. Without
    /// it the player floats in the sea and the world stops making sense.
    private func buildSteppingStones() {
        let stones = CGMutablePath()
        for line in 0..<terrain.rowCount where terrain.lineStyles[line] == .blank {
            let rect = cellRect(line: line, col: 0).insetBy(dx: 4, dy: 5)
            stones.addRoundedRect(in: rect, cornerWidth: 8, cornerHeight: 8)
        }
        guard !stones.isEmpty else { return }
        let node = SKShapeNode(path: stones)
        node.fillColor = GameTheme.nsColor(GameTheme.groundTile.opacity(0.5))
        node.strokeColor = GameTheme.nsColor(GameTheme.tornEdge.opacity(0.35))
        node.lineWidth = 1.4
        node.zPosition = 0.05
        decorLayer.addChild(node)
    }

    /// Notebook rules under indented and list rows — the paths of this world.
    /// The rule runs under the WHOLE row, not just its gaps, so the path reads
    /// as continuous beneath the words standing on it.
    private func buildRuledPaths() {
        let rules = CGMutablePath()
        for line in 0..<terrain.rowCount where terrain.lineStyles[line] == .path {
            guard let span = terrain.landSpan(line: line) else { continue }
            let rect = runRect(line: line, columns: span)
            rules.move(to: CGPoint(x: rect.minX, y: rect.minY + tileH * 0.16))
            rules.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tileH * 0.16))
        }
        guard !rules.isEmpty else { return }
        let node = SKShapeNode(path: rules)
        node.strokeColor = GameTheme.nsColor(GameTheme.ruleLine)
        node.lineWidth = 2
        node.alpha = 0.75
        node.fillColor = .clear
        node.zPosition = 0.1
        decorLayer.addChild(node)
    }

    /// Heading lines become signpost banners: a brighter strip with an amber
    /// border and a nail at each end.
    private func buildBanners() {
        let banners = CGMutablePath()
        let nails = CGMutablePath()
        for line in 0..<terrain.rowCount where terrain.lineStyles[line] == .heading {
            guard let span = terrain.landSpan(line: line) else { continue }
            let rect = runRect(line: line, columns: span).insetBy(dx: -4, dy: 2)
            banners.addRoundedRect(in: rect, cornerWidth: 5, cornerHeight: 5)
            for x in [rect.minX + 8, rect.maxX - 8] {
                nails.addEllipse(in: CGRect(x: x - 2.4, y: rect.midY - 2.4, width: 4.8, height: 4.8))
            }
        }
        guard !banners.isEmpty else { return }
        let strip = SKShapeNode(path: banners)
        strip.fillColor = GameTheme.nsColor(GameTheme.bannerTile)
        strip.strokeColor = GameTheme.nsColor(GameTheme.vimkinAmber)
        strip.lineWidth = 2.5
        strip.zPosition = 0.2
        decorLayer.addChild(strip)

        let nailNode = SKShapeNode(path: nails)
        nailNode.fillColor = GameTheme.nsColor(GameTheme.vimkinAmber)
        nailNode.strokeColor = .clear
        nailNode.zPosition = 0.3
        decorLayer.addChild(nailNode)
    }

    /// A run of non-space characters is a WORD, and a word is a raised plank of
    /// paper you walk along — one rounded tile per word, not per letter, so the
    /// world reads as word-platforms (which is exactly what `w` jumps between).
    /// Faint dividers keep the individual cells countable for `h`/`l`.
    private func buildLetterTiles() {
        let faces = CGMutablePath()
        let lips = CGMutablePath()
        let dividers = CGMutablePath()
        for run in terrain.landRuns() where run.kind == .letter {
            // Heading glyphs ride on their banner; they get no separate plank.
            guard terrain.lineStyles[run.line] != .heading else { continue }
            let rect = runRect(line: run.line, columns: run.columns).insetBy(dx: 1.5, dy: 2.5)
            faces.addRoundedRect(in: rect, cornerWidth: 5, cornerHeight: 5)
            lips.addRoundedRect(
                in: rect.offsetBy(dx: 0, dy: -2.5), cornerWidth: 5, cornerHeight: 5
            )
            for col in run.columns.dropFirst() {
                let x = cellRect(line: run.line, col: col).minX
                dividers.move(to: CGPoint(x: x, y: rect.minY + 4))
                dividers.addLine(to: CGPoint(x: x, y: rect.maxY - 4))
            }
        }
        guard !faces.isEmpty else { return }
        let lip = SKShapeNode(path: lips)
        lip.fillColor = GameTheme.nsColor(GameTheme.tileShadow)
        lip.strokeColor = .clear
        lip.alpha = 0.6
        lip.zPosition = 0.4
        decorLayer.addChild(lip)

        let face = SKShapeNode(path: faces)
        face.fillColor = GameTheme.nsColor(GameTheme.letterTile)
        face.strokeColor = GameTheme.nsColor(GameTheme.tornEdge)
        face.lineWidth = 0.8
        face.zPosition = 0.5
        decorLayer.addChild(face)

        let seams = SKShapeNode(path: dividers)
        seams.strokeColor = GameTheme.nsColor(GameTheme.glyphInk)
        seams.lineWidth = 0.7
        seams.alpha = 0.14
        seams.fillColor = .clear
        seams.zPosition = 0.55
        decorLayer.addChild(seams)
    }

    /// The torn-paper rim: the one touch that makes the page read as an ISLAND.
    /// Drawn only along sides that actually face the sea, with a per-cell wobble
    /// so the edge is hand-torn rather than milled.
    private func buildIslandRim() {
        let path = CGMutablePath()
        for segment in terrain.rimSegments() {
            let rect = cellRect(line: segment.line, col: segment.col)
            var wobble = Wobble(seed: UInt64(bitPattern: Int64(segment.line &* 733 &+ segment.col)))
            for side in TerrainMap.Side.allCases where segment.sides.contains(side) {
                let (from, to): (CGPoint, CGPoint)
                switch side {
                case .top:
                    from = CGPoint(x: rect.minX, y: rect.maxY)
                    to = CGPoint(x: rect.maxX, y: rect.maxY)
                case .bottom:
                    from = CGPoint(x: rect.minX, y: rect.minY)
                    to = CGPoint(x: rect.maxX, y: rect.minY)
                case .leading:
                    from = CGPoint(x: rect.minX, y: rect.minY)
                    to = CGPoint(x: rect.minX, y: rect.maxY)
                case .trailing:
                    from = CGPoint(x: rect.maxX, y: rect.minY)
                    to = CGPoint(x: rect.maxX, y: rect.maxY)
                }
                let horizontal = abs(to.x - from.x) > abs(to.y - from.y)
                path.move(to: from)
                for step in 1...3 {
                    let t = CGFloat(step) / 3
                    let jitter = CGFloat(wobble.signed(1.3))
                    path.addLine(to: CGPoint(
                        x: from.x + (to.x - from.x) * t + (horizontal ? 0 : jitter),
                        y: from.y + (to.y - from.y) * t + (horizontal ? jitter : 0)
                    ))
                }
            }
        }
        guard !path.isEmpty else { return }
        let halo = SKShapeNode(path: path)
        halo.strokeColor = GameTheme.nsColor(GameTheme.tornEdge)
        halo.lineWidth = 6
        halo.alpha = 0.12
        halo.fillColor = .clear
        halo.zPosition = 0.1
        rimLayer.addChild(halo)

        let edge = SKShapeNode(path: path)
        edge.strokeColor = GameTheme.nsColor(GameTheme.tornEdge)
        edge.lineWidth = 2.2
        edge.alpha = 0.9
        edge.fillColor = .clear
        edge.zPosition = 0.2
        rimLayer.addChild(edge)
    }

    /// Graph-paper blocks and the red rule down the page's left margin — the
    /// world's walls, and the thing that makes it read as a notebook page.
    private func buildMarginWall() {
        guard terrain.rowCount > 0 else { return }
        let blocks = CGMutablePath()
        let grid = CGMutablePath()
        let texture = Self.spriteCache.texture(
            named: Self.marginWallTexture, in: Self.tileDirectory
        )
        for line in 0..<terrain.rowCount {
            for col in -Self.marginColumns ..< 0 {
                let rect = cellRect(line: line, col: col).insetBy(dx: 1, dy: 1)
                if let texture {
                    let node = SKSpriteNode(texture: texture)
                    node.size = rect.size
                    node.position = CGPoint(x: rect.midX, y: rect.midY)
                    marginLayer.addChild(node)
                    continue
                }
                blocks.addRoundedRect(in: rect, cornerWidth: 2, cornerHeight: 2)
                grid.move(to: CGPoint(x: rect.minX, y: rect.midY))
                grid.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                grid.move(to: CGPoint(x: rect.midX, y: rect.minY))
                grid.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
        if !blocks.isEmpty {
            let wall = SKShapeNode(path: blocks)
            wall.fillColor = GameTheme.nsColor(GameTheme.marginWall)
            wall.strokeColor = GameTheme.nsColor(GameTheme.marginGrid)
            wall.lineWidth = 1
            wall.zPosition = 0.1
            marginLayer.addChild(wall)

            let grating = SKShapeNode(path: grid)
            grating.strokeColor = GameTheme.nsColor(GameTheme.marginGrid)
            grating.lineWidth = 0.7
            grating.alpha = 0.6
            grating.fillColor = .clear
            grating.zPosition = 0.2
            marginLayer.addChild(grating)
        }

        let top = cellRect(line: 0, col: 0)
        let bottom = cellRect(line: terrain.rowCount - 1, col: 0)
        let rulePath = CGMutablePath()
        rulePath.move(to: CGPoint(x: top.minX - 5, y: top.maxY + 6))
        rulePath.addLine(to: CGPoint(x: bottom.minX - 5, y: bottom.minY - 6))
        let rule = SKShapeNode(path: rulePath)
        rule.strokeColor = GameTheme.nsColor(GameTheme.marginRule)
        rule.lineWidth = 2
        rule.alpha = 0.55
        rule.fillColor = .clear
        rule.zPosition = 0.3
        marginLayer.addChild(rule)
    }

    /// If a generated tileset is in the bundle, lay it over the programmatic
    /// terrain — one `SKTileMapNode` for the whole grid, not a sprite per cell.
    /// Absent art is the normal case and costs nothing.
    private func buildTileArt() {
        guard terrain.rowCount > 0, terrain.columnCount > 0 else { return }
        var groups: [TerrainKind: SKTileGroup] = [:]
        for kind in TerrainKind.allCases {
            guard let texture = Self.spriteCache.texture(
                named: kind.textureName, in: Self.tileDirectory
            ) else { continue }
            let definition = SKTileDefinition(texture: texture, size: CGSize(width: tileW, height: tileH))
            groups[kind] = SKTileGroup(tileDefinition: definition)
        }
        guard !groups.isEmpty else { return }

        let map = SKTileMapNode(
            tileSet: SKTileSet(tileGroups: Array(groups.values)),
            columns: terrain.columnCount,
            rows: terrain.rowCount,
            tileSize: CGSize(width: tileW, height: tileH)
        )
        for line in 0..<terrain.rowCount {
            for col in 0..<terrain.columnCount {
                let kind = terrain.kind(line: line, col: col)
                // The sea is the scene's own background; never paper over it.
                guard kind.isLand, let group = groups[kind] else { continue }
                map.setTileGroup(group, forColumn: col, row: terrain.rowCount - 1 - line)
            }
        }
        let origin = geometry.scenePoint(line: 0, col: 0)
        map.position = CGPoint(
            x: origin.x + CGFloat(terrain.columnCount) * tileW / 2,
            y: origin.y + tileH - CGFloat(terrain.rowCount) * tileH / 2
        )
        tileArtLayer.addChild(map)
    }

    // MARK: - Glyphs

    /// One label per LINE, kerned so each character's advance is exactly one
    /// tile. That decouples the glyph size from the grid (letters can be small
    /// and centred on chunky tiles) while still costing one node per row.
    private func buildGlyphs() {
        let body = NSFont.monospacedSystemFont(ofSize: Self.glyphSize, weight: .medium)
        let heading = NSFont.monospacedSystemFont(ofSize: Self.glyphSize, weight: .bold)
        let advance = NSAttributedString(string: "M", attributes: [.font: body]).size().width

        for line in 0..<terrain.rowCount {
            let length = terrain.contentLengths[line]
            guard length > 0 else { continue }
            let text = String(terrain.lines[line].prefix(length))
            let font = terrain.lineStyles[line] == .heading ? heading : body

            let node = SKLabelNode()
            node.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: GameTheme.nsColor(GameTheme.glyphInk),
                    .kern: tileW - advance,
                ]
            )
            node.horizontalAlignmentMode = .left
            node.verticalAlignmentMode = .baseline
            let cell = cellRect(line: line, col: 0)
            node.position = CGPoint(
                x: cell.minX + (tileW - advance) / 2,
                y: cell.midY - font.capHeight / 2
            )
            glyphLayer.addChild(node)
        }
    }

    // MARK: - Vimkins

    private func rebuildVimkins() {
        vimkinLayer.removeAllChildren()
        markerLayer.removeAllChildren()
        vimkinNodes.removeAll()

        for vimkin in state.level.vimkins {
            let node = VimkinNode(cellSize: Self.tile)
            vimkinLayer.addChild(node)
            vimkinNodes[vimkin.id] = node

            let marker = SKShapeNode(circleOfRadius: tileH * 1.15)
            // A soft lantern-glow, not a targeting reticle: it must help you
            // spot a Vimkin in dense prose without competing with the art.
            marker.strokeColor = .clear
            marker.lineWidth = 0
            marker.fillColor = GameTheme.nsColor(GameTheme.vimkinAmber.opacity(0.16))
            marker.name = vimkin.id
            marker.run(.repeatForever(.sequence([
                .scale(to: 1.12, duration: 1.1), .scale(to: 1.0, duration: 1.1),
            ])))
            markerLayer.addChild(marker)
        }
        layoutVimkins()
    }

    private func layoutVimkins() {
        for vimkin in state.level.vimkins {
            let rect = cellRect(line: vimkin.position.line, col: vimkin.position.col)
            // Standing ON the tile: feet at the tile, body rising above it.
            let point = CGPoint(x: rect.midX, y: rect.midY + tileH * 0.45)
            let rescued = state.isRescued(vimkin)

            vimkinNodes[vimkin.id]?.position = point
            vimkinNodes[vimkin.id]?.setRescued(rescued)
            if let marker = markerLayer.children.first(where: { $0.name == vimkin.id }) {
                marker.position = CGPoint(x: rect.midX, y: rect.midY)
                marker.isHidden = rescued
            }
        }
    }

    // MARK: - The cursor-spirit

    private func buildPlayer() {
        let body = SKShapeNode(
            rect: CGRect(x: -tileW / 2, y: -tileH / 2, width: tileW, height: tileH)
                .insetBy(dx: 0.5, dy: 1),
            cornerRadius: 5
        )
        body.fillColor = GameTheme.nsColor(GameTheme.cursorCyan.opacity(0.9))
        body.strokeColor = GameTheme.nsColor(GameTheme.tornEdge)
        body.lineWidth = 2

        let glow = SKShapeNode(circleOfRadius: tileH * 1.15)
        glow.fillColor = GameTheme.nsColor(GameTheme.cursorCyan.opacity(0.30))
        glow.strokeColor = .clear
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.5, duration: 0.9), .fadeAlpha(to: 1.0, duration: 0.9),
        ])))

        glow.zPosition = 0
        body.zPosition = 1
        let node = SKNode()
        node.zPosition = 1
        node.addChild(glow)
        node.addChild(body)
        playerLayer.addChild(node)
        player = node
        playerGlow = glow

        // The motion trail: fading afterimages the player drags behind it.
        trailNodes = (0..<Self.trailLength).map { index in
            let ghost = SKShapeNode(
                rect: CGRect(x: -tileW / 2, y: -tileH / 2, width: tileW, height: tileH)
                    .insetBy(dx: 1.5, dy: 2),
                cornerRadius: 4
            )
            let fade = 0.42 * (1 - Double(index) / Double(Self.trailLength))
            ghost.fillColor = GameTheme.nsColor(GameTheme.cursorCyan.opacity(fade))
            ghost.strokeColor = .clear
            ghost.zPosition = 0
            ghost.isHidden = true
            playerLayer.addChild(ghost)
            return ghost
        }
    }

    private func movePlayer(to cursor: Position, animated: Bool) {
        guard let player else { return }
        let rect = cellRect(line: cursor.line, col: cursor.col)
        let target = CGPoint(x: rect.midX, y: rect.midY)
        guard target != player.position else { return }

        if animated {
            // Push the old positions down the trail, newest first.
            var previous = player.position
            for ghost in trailNodes {
                let carried = ghost.position
                ghost.position = previous
                ghost.isHidden = false
                ghost.alpha = 1
                ghost.run(.fadeOut(withDuration: 0.35))
                previous = carried
            }
            player.run(.move(to: target, duration: 0.075))
        } else {
            player.position = target
            for ghost in trailNodes {
                ghost.position = target
                ghost.isHidden = true
            }
        }
    }

    // MARK: - Camera

    /// Eases the camera onto the player, clamped by `TileCamera` so the sea
    /// never opens up more than a tile past the world's edge — and so a page
    /// smaller than the window stays centred instead of sliding around.
    private func moveCamera(animated: Bool) {
        let rect = cellRect(line: state.engine.cursor.line, col: state.engine.cursor.col)
        let clamped = TileCamera.clamp(
            target: LayoutPoint(x: Double(rect.midX), y: Double(rect.midY)),
            world: worldRect,
            viewport: LayoutSize(width: Double(size.width), height: Double(size.height)),
            margin: Self.tile.width
        )
        let point = CGPoint(x: clamped.x, y: clamped.y)
        guard animated else {
            cameraNode.removeAction(forKey: "follow")
            cameraNode.position = point
            return
        }
        guard point != cameraNode.position else { return }
        let follow = SKAction.move(to: point, duration: Self.followDuration)
        follow.timingMode = .easeOut
        cameraNode.run(follow, withKey: "follow")
    }

    // MARK: - Feedback

    /// A locked key: a friendly shimmer, never a failure animation.
    public func shimmer() {
        playerGlow?.removeAllActions()
        playerGlow?.run(.sequence([
            .scale(to: 1.5, duration: 0.09),
            .scale(to: 1.0, duration: 0.16),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.5, duration: 0.9), .fadeAlpha(to: 1.0, duration: 0.9),
            ])),
        ]))
    }

    /// A Vimkin pops free: its lantern-belly lights and it drifts upward.
    public func pop(_ vimkin: Vimkin) {
        vimkinNodes[vimkin.id]?.celebrate()
    }
}

// MARK: - Deterministic wobble

/// A tiny LCG. The torn edge and the sea must look hand-made but must NOT
/// change between frames or between runs, so randomness is seeded per cell.
struct Wobble {
    private var seed: UInt64

    init(seed: UInt64) {
        self.seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    mutating func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((seed >> 33) & 0xFFFF) / 65_535.0
    }

    mutating func signed(_ amplitude: Double) -> Double { (next() * 2 - 1) * amplitude }
}

// MARK: - The Vimkin sprite

/// Programmatic fallback for the generated art: a round ink body with an amber
/// lantern-belly and one tuft of pen-stroke hair. Sized at ~2 tiles so the
/// creature reads as a character standing on the map, not as a glyph.
final class VimkinNode: SKNode {
    private let body: SKShapeNode
    private let belly: SKShapeNode
    private let tuft: SKShapeNode
    /// The drawn creature, when its art is in the bundle. When absent the
    /// programmatic shapes above stand in, so the game never depends on art
    /// having been generated.
    private var sprite: SKSpriteNode?
    private static let spriteCache = SpriteCache()

    /// Loads a cut-out character PNG from `Content/sprites/`, or nil if the art
    /// was never generated for this build.
    private static func texture(named name: String) -> SKTexture? {
        spriteCache.texture(named: name)
    }

    init(cellSize: LayoutSize) {
        let radius = CGFloat(cellSize.height) * 0.42
        body = SKShapeNode(circleOfRadius: radius)
        belly = SKShapeNode(circleOfRadius: radius * 0.45)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius * 0.9))
        path.addQuadCurve(
            to: CGPoint(x: radius * 0.55, y: radius * 1.7),
            control: CGPoint(x: radius * 0.9, y: radius * 1.1)
        )
        tuft = SKShapeNode(path: path)
        super.init()

        body.fillColor = GameTheme.nsColor(GameTheme.plumDark)
        body.strokeColor = GameTheme.nsColor(GameTheme.parchment.opacity(0.75))
        body.lineWidth = 1.4
        belly.position = CGPoint(x: 0, y: -radius * 0.18)
        belly.fillColor = GameTheme.nsColor(GameTheme.vimkinAmber.opacity(0.45))
        belly.strokeColor = .clear
        tuft.strokeColor = GameTheme.nsColor(GameTheme.parchment.opacity(0.75))
        tuft.lineWidth = 1.4
        tuft.fillColor = .clear

        body.zPosition = 0
        belly.zPosition = 0.1
        tuft.zPosition = 0.2
        // A contact shadow, so the creature stands ON the tile instead of
        // hovering in front of it.
        let contact = SKShapeNode(ellipseOf: CGSize(width: radius * 2.2, height: radius * 0.7))
        contact.position = CGPoint(x: 0, y: -CGFloat(cellSize.height) * 0.45)
        contact.fillColor = GameTheme.nsColor(GameTheme.tileShadow)
        contact.strokeColor = .clear
        contact.alpha = 0.4
        contact.zPosition = -0.1

        addChild(contact)
        addChild(body)
        addChild(belly)
        addChild(tuft)

        if let texture = Self.texture(named: "vimkin-base-trapped") {
            let node = SKSpriteNode(texture: texture)
            // ~2.2 tiles tall on purpose — the creature should read as a
            // character standing in the text, not as a glyph.
            let side = CGFloat(cellSize.height) * 2.2
            node.size = CGSize(width: side, height: side)
            node.zPosition = 1
            addChild(node)
            sprite = node
            // The shapes are the fallback silhouette; hide them behind real art.
            body.isHidden = true
            belly.isHidden = true
            tuft.isHidden = true
        }

        run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 1.6, duration: 1.3),
            .moveBy(x: 0, y: -1.6, duration: 1.3),
        ])))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("VimkinNode is created in code") }

    func setRescued(_ rescued: Bool) {
        belly.fillColor = GameTheme.nsColor(
            GameTheme.vimkinAmber.opacity(rescued ? 1.0 : 0.45)
        )
        body.strokeColor = GameTheme.nsColor(
            (rescued ? GameTheme.vimkinAmber : GameTheme.parchment).opacity(0.85)
        )
        if let sprite,
           let texture = Self.texture(named: rescued ? "vimkin-base-rescued" : "vimkin-base-trapped") {
            sprite.texture = texture
        }
    }

    /// The rescue beat: the lantern flares and the creature hops.
    func celebrate() {
        setRescued(true)
        belly.run(.sequence([
            .scale(to: 2.0, duration: 0.14),
            .scale(to: 1.0, duration: 0.22),
        ]))
        run(.sequence([
            .moveBy(x: 0, y: 9, duration: 0.14),
            .moveBy(x: 0, y: -9, duration: 0.2),
        ]))
    }
}
