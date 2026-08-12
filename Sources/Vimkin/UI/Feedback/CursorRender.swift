// CursorRender.swift — the numbers behind the animated cursor.
//
// The cursor is the player's avatar in this app, so it is written as a
// character, not a rectangle: it TRAVELS (eased, with a trail whose length
// scales with the size of the jump, so `G` feels nothing like `l`), it LANDS
// (squash on impact, then settle), it BREATHES at rest, and it MORPHS between
// mode shapes with a colour shift and a ring.
//
// Everything here is pure arithmetic on values — no SwiftUI, no clocks, no
// state — so the renderer stays a thin "draw what this says" layer and the feel
// can be tuned in one place.

import CoreGraphics
import Foundation

/// A cursor journey between two buffer cells, in cell coordinates so it stays
/// correct across scrolling (view coordinates are derived at draw time).
public struct CursorFlight: Equatable, Sendable {
    public let from: Position
    public let to: Position
    public let start: Date
    public let duration: TimeInterval

    public init(from: Position, to: Position, start: Date) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = CursorRender.flightDuration(cells: CursorRender.distance(from: from, to: to))
    }

    /// How far the cursor travelled, in "feel" cells (a line counts for more
    /// than a column — a `j` should read as a bigger move than an `l`).
    public var cells: Double { CursorRender.distance(from: from, to: to) }
}

/// A mode change, for the morph + ring.
public struct ModeShift: Equatable, Sendable {
    public let from: Mode
    public let to: Mode
    public let start: Date

    public init(from: Mode, to: Mode, start: Date) {
        self.from = from
        self.to = to
        self.start = start
    }

    /// Entering Insert is the dramatic one — block becomes a bar, and a ring
    /// goes out. Leaving snaps back with a quicker, tighter shock.
    public var isEnteringInsert: Bool { to == .insert && from != .insert }
    public var isLeavingInsert: Bool { from == .insert && to != .insert }
}

public enum CursorRender {

    // MARK: - Timing

    /// Travel time for a jump of `cells`. Short hops are near-instant; a jump
    /// across the document takes long enough to read as a flight, and never so
    /// long that the editor feels laggy.
    public static func flightDuration(cells: Double) -> TimeInterval {
        min(0.30, 0.075 + 0.016 * max(cells, 0))
    }

    /// Weighted distance between two cells (lines weigh more than columns).
    public static func distance(from: Position, to: Position) -> Double {
        let lines = Double(abs(to.line - from.line)) * 2.2
        let cols = Double(abs(to.col - from.col))
        return (lines * lines + cols * cols).squareRoot()
    }

    /// How many after-images the trail carries. A big jump smears; `l` doesn't.
    public static func trailCount(cells: Double) -> Int {
        min(9, max(0, Int((cells / 1.6).rounded(.down))))
    }

    // MARK: - Easing

    public static func clamp01(_ t: Double) -> Double { min(max(t, 0), 1) }

    /// Fast out, drifting to a stop.
    public static func easeOutCubic(_ t: Double) -> Double {
        let x = clamp01(t)
        return 1 - pow(1 - x, 3)
    }

    /// A single hump, 0 → 1 → 0. Drives squash, ripples and the reward burst.
    public static func hump(_ t: Double) -> Double {
        let x = clamp01(t)
        return sin(x * .pi)
    }

    /// The idle breath: a slow, shallow glow that never distracts.
    public static func restingGlow(at time: TimeInterval) -> Double {
        0.42 + 0.22 * sin(time * 2.4)
    }

    // MARK: - Shape

    /// The cursor's resting silhouette for a mode, inside its cell.
    public static func silhouette(mode: Mode, cell: CGRect) -> CGRect {
        switch mode {
        case .insert:
            // A bar on the leading edge — you type BETWEEN characters.
            return CGRect(x: cell.minX - 1.4, y: cell.minY - 1, width: 2.8, height: cell.height + 2)
        case .operatorPending:
            // Waiting for a noun: a low underline, deliberately unfinished.
            return CGRect(x: cell.minX, y: cell.maxY - 3, width: cell.width, height: 3)
        case .normal, .visual, .commandLine:
            return cell
        }
    }

    /// Morph between two silhouettes.
    public static func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let x = clamp01(t)
        func mix(_ lhs: Double, _ rhs: Double) -> Double { lhs + (rhs - lhs) * x }
        return CGRect(
            x: mix(a.minX, b.minX),
            y: mix(a.minY, b.minY),
            width: mix(a.width, b.width),
            height: mix(a.height, b.height)
        )
    }

    /// Impact deformation: wide-and-short right after landing, settling back.
    /// `landing` is 0 at touchdown and 1 once settled.
    public static func squashed(_ rect: CGRect, landing: Double, along horizontal: Bool) -> CGRect {
        let punch = hump(landing) * 0.34
        guard punch > 0.0001 else { return rect }
        let wide = horizontal ? 1 + punch : 1 - punch * 0.6
        let tall = horizontal ? 1 - punch * 0.6 : 1 + punch
        let width = rect.width * wide
        let height = rect.height * tall
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Durations of the one-shot flourishes

    /// How long the landing squash takes to settle.
    public static let landingDuration: TimeInterval = 0.17
    /// How long the block↔bar morph takes.
    public static let morphDuration: TimeInterval = 0.16
    /// How long a mode ring lives.
    public static let ringDuration: TimeInterval = 0.42
    /// How long a correct-rep burst lives.
    public static let rewardDuration: TimeInterval = 0.55
    /// How long ghost cursors take to fade once the learner commits.
    public static let ghostFadeDuration: TimeInterval = 0.34
}
