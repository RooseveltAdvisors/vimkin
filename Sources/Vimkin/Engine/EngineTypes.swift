// EngineTypes.swift — core value types for VimEngine.
// Pure Swift: no AppKit/SwiftUI imports anywhere in Engine/.

/// A single key delivered to the engine.
public enum KeyInput: Equatable, Hashable, Sendable {
    case char(Character)
    case escape
    case enter
}

extension KeyInput: ExpressibleByExtendedGraphemeClusterLiteral {
    public init(unicodeScalarLiteral value: Character) { self = .char(value) }
    public init(extendedGraphemeClusterLiteral value: Character) { self = .char(value) }
}

/// Editor mode.
public enum Mode: String, Equatable, Sendable {
    case normal
    case insert
    case visual            // charwise visual (v); linewise V is out of v1 scope
    case operatorPending
    case commandLine
}

/// A cursor position: 0-based line and column (column counts Characters).
public struct Position: Equatable, Hashable, Comparable, Sendable {
    public var line: Int
    public var col: Int

    public init(line: Int, col: Int) {
        self.line = line
        self.col = col
    }

    public static func < (lhs: Position, rhs: Position) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.col < rhs.col
    }
}
