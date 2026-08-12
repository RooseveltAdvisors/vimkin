// SeededGenerator.swift — SplitMix64, so a dojo session is reproducible from a
// seed (tests, and later the date-seeded arcade run in U12). Deterministic and
// dependency-free; the same seed always yields the same drill sequence.

/// SplitMix64 PRNG. Fast, well-distributed, and — unlike
/// `SystemRandomNumberGenerator` — reproducible.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A random source the generator can hold as a value: either seeded
/// (deterministic) or the system source (ordinary play).
enum DrillRandomSource {
    case seeded(SeededGenerator)
    case system(SystemRandomNumberGenerator)

    init(seed: UInt64?) {
        if let seed {
            self = .seeded(SeededGenerator(seed: seed))
        } else {
            self = .system(SystemRandomNumberGenerator())
        }
    }

    /// A uniform value in `0..<upperBound` (0 when the bound is not positive).
    mutating func next(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        switch self {
        case .seeded(var generator):
            let value = Int(generator.next(upperBound: UInt64(upperBound)))
            self = .seeded(generator)
            return value
        case .system(var generator):
            let value = Int(generator.next(upperBound: UInt64(upperBound)))
            self = .system(generator)
            return value
        }
    }

    /// A uniform value in `0..<1`.
    mutating func nextUnit() -> Double {
        let scale = 1 << 53
        return Double(next(upperBound: scale)) / Double(scale)
    }
}
