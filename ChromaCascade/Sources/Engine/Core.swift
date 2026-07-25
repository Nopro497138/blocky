import Foundation

// MARK: - Colours

/// The palette. Raw values double as the board's cell encoding, 0 meaning empty.
enum BlockColor: UInt8, CaseIterable {
    case cyan = 1
    case magenta = 2
    case lime = 3
    case amber = 4
    case violet = 5
    case coral = 6

    /// The first `count` colours, i.e. the palette a given stage plays with.
    static func palette(count: Int) -> [BlockColor] {
        let all = BlockColor.allCases
        let n = max(1, min(count, all.count))
        return Array(all[0..<n])
    }
}

// MARK: - Grid geometry

struct GridPoint: Hashable {
    var row: Int
    var col: Int

    init(_ row: Int, _ col: Int) {
        self.row = row
        self.col = col
    }
}

/// A cell that slid down after a detonation, so the renderer can animate it.
struct FallMove {
    let from: GridPoint
    let to: GridPoint
    let color: BlockColor
}

// MARK: - Pieces

struct PieceShape {
    let id: String
    let cells: [GridPoint]
    let weight: Int

    var size: Int { cells.count }

    var width: Int {
        (cells.map { $0.col }.max() ?? 0) + 1
    }

    var height: Int {
        (cells.map { $0.row }.max() ?? 0) + 1
    }
}

struct Piece {
    let shape: PieceShape
    let color: BlockColor
    /// Stable identity so the renderer can track a tray slot across refills.
    let serial: Int
}

// MARK: - Deterministic RNG

/// SplitMix64 — small, fast and reproducible, which makes runs replayable from a
/// seed and lets the balance simulator and the game agree on the same numbers.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(below limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        return Int(next() % UInt64(limit))
    }

    mutating func double() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}
