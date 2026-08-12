// GameScene.swift — the SpriteKit tile world (plan U7).
//
// Renders a GameState as terrain: the document's characters ARE the world, laid
// out through the shared `BufferLayout` geometry (via GameGeometry) so the game
// and the editor can never disagree about where a cell is. On top of the
// terrain sit the cursor-spirit (a glowing block of light with a fading trail),
// the trapped Vimkins (amber-bellied ink creatures), and their goal markers.
//
// Deliberately thin: it owns NO game rules. It is handed a GameState after
// every key and redraws. All decisions live in GameState; all geometry lives in
// GameGeometry. Art here is programmatic placeholder work — U8 swaps in the
// generated sprites and hangs particles/audio off `flash(_:)` and `pop(_:)`.

import SpriteKit
import SwiftUI

public final class GameScene: SKScene {

    // MARK: - Tunables

    /// Monospaced cell metrics. 0.6 is the advance ratio of SF Mono-ish faces;
    /// the label font size is derived from it so glyphs sit on the grid.
    private let fontSize: CGFloat = 17
    private var cellSize: LayoutSize {
        LayoutSize(width: Double(fontSize) * 0.6, height: Double(fontSize) * 1.45)
    }
    private static let trailLength = 6

    // MARK: - Nodes

    private let terrainLayer = SKNode()
    private let markerLayer = SKNode()
    private let vimkinLayer = SKNode()
    private let playerLayer = SKNode()

    private var lineNodes: [Int: SKLabelNode] = [:]
    private var vimkinNodes: [String: VimkinNode] = [:]
    private var trailNodes: [SKShapeNode] = []
    private var player: SKNode!
    private var playerGlow: SKShapeNode!

    private var geometry: GameGeometry
    private var state: GameState
    private var lastRenderedLines: [String] = []

    // MARK: - Init

    public init(state: GameState, size: CGSize) {
        self.state = state
        self.geometry = GameGeometry.make(
            lines: state.documentLines,
            cellSize: LayoutSize(width: 17 * 0.6, height: 17 * 1.45),
            viewportSize: LayoutSize(width: Double(size.width), height: Double(size.height))
        )
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = GameTheme.nsColor(GameTheme.inkNavy)
        addChild(terrainLayer)
        addChild(markerLayer)
        addChild(vimkinLayer)
        addChild(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("GameScene is created in code") }

    public override func didMove(to view: SKView) {
        buildPlayer()
        rebuildTerrain()
        rebuildVimkins()
        refresh()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        geometry = GameGeometry.make(
            lines: state.documentLines,
            cellSize: cellSize,
            viewportSize: LayoutSize(width: Double(size.width), height: Double(size.height))
        )
        guard player != nil else { return }
        rebuildTerrain()
        rebuildVimkins()
        refresh()
    }

    // MARK: - State updates (called by GameView after every key)

    /// Applies a new state and animates the difference.
    public func apply(_ newState: GameState, step: GameStep?) {
        let textChanged = newState.documentLines != lastRenderedLines
        state = newState
        if textChanged { rebuildTerrain() }
        refresh()

        if let step, step.wasBlocked { shimmer() }
        for vimkin in step?.newlyRescued ?? [] { pop(vimkin) }
    }

    /// The whole visible frame: scroll, player, vimkin states.
    private func refresh() {
        geometry.reveal(state.engine.cursor)
        layoutTerrain()
        layoutVimkins()
        movePlayer(to: state.engine.cursor)
    }

    // MARK: - Terrain (the document as a tile world)

    private func rebuildTerrain() {
        terrainLayer.removeAllChildren()
        lineNodes.removeAll()
        lastRenderedLines = state.documentLines

        for (index, text) in state.documentLines.enumerated() {
            let node = SKLabelNode(text: text.isEmpty ? " " : text)
            node.fontName = "SFMono-Regular"
            node.fontSize = fontSize
            node.fontColor = GameTheme.nsColor(
                Self.isStructureLine(text) ? GameTheme.terrainStructure : GameTheme.terrain
            )
            node.horizontalAlignmentMode = .left
            node.verticalAlignmentMode = .baseline
            node.zPosition = 1
            terrainLayer.addChild(node)
            lineNodes[index] = node
        }
    }

    /// Markdown/YAML/JSON structure reads brighter — headers are stone gates,
    /// keys are signposts, braces are vaulted doors (style guide, "World").
    private static func isStructureLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("#") || trimmed.hasPrefix("*") || trimmed.hasPrefix("-")
            || trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("[")
    }

    private func layoutTerrain() {
        let visible = geometry.visibleLines(count: state.documentLines.count)
        for (index, node) in lineNodes {
            guard visible.contains(index) else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let origin = geometry.sceneLineOrigin(line: index)
            // Baseline sits a little above the cell's bottom edge.
            node.position = CGPoint(x: origin.x, y: origin.y + geometry.layout.cellSize.height * 0.28)
        }
    }

    // MARK: - Vimkins

    private func rebuildVimkins() {
        vimkinLayer.removeAllChildren()
        markerLayer.removeAllChildren()
        vimkinNodes.removeAll()

        for vimkin in state.level.vimkins {
            let node = VimkinNode(cellSize: geometry.layout.cellSize)
            node.zPosition = 3
            vimkinLayer.addChild(node)
            vimkinNodes[vimkin.id] = node

            let marker = SKShapeNode(
                circleOfRadius: CGFloat(geometry.layout.cellSize.height) * 0.85
            )
            marker.strokeColor = GameTheme.nsColor(GameTheme.vimkinAmber.opacity(0.35))
            marker.lineWidth = 1
            marker.fillColor = .clear
            marker.zPosition = 2
            marker.name = vimkin.id
            marker.run(.repeatForever(.sequence([
                .scale(to: 1.12, duration: 1.1), .scale(to: 1.0, duration: 1.1),
            ])))
            markerLayer.addChild(marker)
        }
    }

    private func layoutVimkins() {
        for vimkin in state.level.vimkins {
            let center = geometry.sceneCenter(line: vimkin.position.line, col: vimkin.position.col)
            let point = CGPoint(x: center.x, y: center.y)
            let rescued = state.isRescued(vimkin)

            if let node = vimkinNodes[vimkin.id] {
                node.position = point
                node.setRescued(rescued)
            }
            markerLayer.children
                .first { $0.name == vimkin.id }?
                .position = point
            markerLayer.children
                .first { $0.name == vimkin.id }
                .map { $0.isHidden = rescued }
        }
    }

    // MARK: - The cursor-spirit

    private func buildPlayer() {
        let cell = geometry.layout.cellSize
        let body = SKShapeNode(
            rect: CGRect(x: -cell.width / 2, y: -cell.height / 2,
                         width: cell.width, height: cell.height),
            cornerRadius: 2
        )
        body.fillColor = GameTheme.nsColor(GameTheme.cursorCyan.opacity(0.85))
        body.strokeColor = .clear

        let glow = SKShapeNode(circleOfRadius: CGFloat(cell.height) * 0.9)
        glow.fillColor = GameTheme.nsColor(GameTheme.cursorCyan.opacity(0.16))
        glow.strokeColor = .clear
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.9), .fadeAlpha(to: 1.0, duration: 0.9),
        ])))

        let node = SKNode()
        node.zPosition = 5
        node.addChild(glow)
        node.addChild(body)
        playerLayer.addChild(node)
        player = node
        playerGlow = glow

        // The motion trail: fading afterimages the player drags behind it.
        trailNodes = (0..<Self.trailLength).map { index in
            let ghost = SKShapeNode(
                rect: CGRect(x: -cell.width / 2, y: -cell.height / 2,
                             width: cell.width, height: cell.height),
                cornerRadius: 2
            )
            let fade = 0.28 * (1 - Double(index) / Double(Self.trailLength))
            ghost.fillColor = GameTheme.nsColor(GameTheme.cursorCyan.opacity(fade))
            ghost.strokeColor = .clear
            ghost.zPosition = 4
            ghost.isHidden = true
            playerLayer.addChild(ghost)
            return ghost
        }
    }

    private func movePlayer(to cursor: Position) {
        guard let player else { return }
        let center = geometry.sceneCenter(line: cursor.line, col: cursor.col)
        let target = CGPoint(x: center.x, y: center.y)
        guard target != player.position else { return }

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
    }

    // MARK: - Feedback (U8 attaches particles + audio here)

    /// A locked key: a friendly shimmer, never a failure animation.
    public func shimmer() {
        playerGlow?.removeAllActions()
        playerGlow?.run(.sequence([
            .scale(to: 1.5, duration: 0.09),
            .scale(to: 1.0, duration: 0.16),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.9), .fadeAlpha(to: 1.0, duration: 0.9),
            ])),
        ]))
    }

    /// A Vimkin pops free: its lantern-belly lights and it drifts upward.
    public func pop(_ vimkin: Vimkin) {
        guard let node = vimkinNodes[vimkin.id] else { return }
        node.celebrate()
    }
}

// MARK: - The Vimkin sprite

/// Programmatic placeholder for the generated art (U8): a round ink body with
/// an amber lantern-belly and one tuft of pen-stroke hair.
final class VimkinNode: SKNode {
    private let body: SKShapeNode
    private let belly: SKShapeNode
    private let tuft: SKShapeNode

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

        addChild(body)
        addChild(belly)
        addChild(tuft)

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
