import Foundation

/// One rung of the difficulty ladder.
struct Stage {
    let firstTurn: Int
    let colors: Int
    /// Cells needed to *start* a detonation.
    let threshold: Int
    let minPiece: Int
    let maxPiece: Int
    let name: String
}

/// Every tunable number lives here. These values are the output of
/// `tools/simulate.js`, which played ~150 runs per candidate configuration with a
/// random, a human-proxy and an expert policy. See DESIGN.md §10 for the targets.
enum GameConfig {

    // Board ---------------------------------------------------------------

    static let cols = 8
    static let rows = 10
    /// Rows near the top that pulse red once the stack reaches them.
    static let dangerRows = 2

    // Detonation ----------------------------------------------------------

    /// How many cells fewer than the opening requirement a follow-up rung of a
    /// cascade needs. Kept at 1 deliberately: an earlier build let follow-up
    /// rungs fire at 3 cells regardless of the stage requirement, which turned
    /// every blast into an automatic board-wide demolition instead of something
    /// the player earned.
    static let chainRelief = 1

    /// A cascade stays inside the colour that started it. Without this a single
    /// placement detonated clusters of every colour at once, which read as the
    /// board falling apart on its own rather than as a colour puzzle.
    static let monoColorChain = true

    // Scoring -------------------------------------------------------------

    static let chainMultipliers: [Double] = [1, 1.6, 2.4, 3.6, 5.2, 7.5, 10, 14, 19, 25]
    static let simultaneityBonus = 0.25
    static let feverScoreMultiplier = 3.0

    /// Size is the reward curve now, so the bonus for overshooting the
    /// requirement grows quadratically and steeply: a 20-cell blob is worth far
    /// more than four 5-cell ones.
    static let sizeBonusFactor = 6

    // Fever ---------------------------------------------------------------

    static let feverHeatNeeded = 10.0
    static let feverHeatDrain = 0.5
    static let feverPlacements = 8
    static let feverExtendPerBlast = 2
    static let feverHeatAfter = 8.0

    /// During fever the tray draws from only this many colours — the ones the
    /// board already holds most of. Fever is an invitation to finish a huge
    /// cluster, not a period where the board clears itself.
    static let feverPaletteSize = 2

    // Power-ups -----------------------------------------------------------

    static let bombEveryPoints = 4000
    static let rerollEveryPoints = 6000
    static let maxCharges = 3

    /// Placements that must pass between two hints.
    static let hintCooldown = 4

    // Difficulty ladder ---------------------------------------------------

    /// Turn count, not score, is the difficulty clock: score-based ramps let a
    /// player plateau at exactly the score where their skill stops paying, and
    /// the run then never ends. See DESIGN.md §4.
    static let stages: [Stage] = [
        Stage(firstTurn: 0,   colors: 4, threshold: 5,  minPiece: 1, maxPiece: 4, name: "SPARK"),
        Stage(firstTurn: 10,  colors: 5, threshold: 5,  minPiece: 1, maxPiece: 4, name: "FLUX"),
        Stage(firstTurn: 24,  colors: 5, threshold: 6,  minPiece: 1, maxPiece: 5, name: "SURGE"),
        Stage(firstTurn: 40,  colors: 6, threshold: 7,  minPiece: 2, maxPiece: 5, name: "PRISM"),
        Stage(firstTurn: 60,  colors: 6, threshold: 8,  minPiece: 2, maxPiece: 5, name: "NOVA"),
        Stage(firstTurn: 85,  colors: 6, threshold: 9,  minPiece: 3, maxPiece: 5, name: "PULSAR"),
        Stage(firstTurn: 115, colors: 6, threshold: 10, minPiece: 3, maxPiece: 5, name: "QUASAR"),
        Stage(firstTurn: 150, colors: 6, threshold: 11, minPiece: 4, maxPiece: 5, name: "SINGULARITY"),
    ]

    static func stageIndex(forTurn turn: Int) -> Int {
        var index = 0
        for (i, stage) in stages.enumerated() where turn >= stage.firstTurn {
            index = i
        }
        return index
    }

    static func stage(forTurn turn: Int) -> Stage {
        stages[stageIndex(forTurn: turn)]
    }

    // Piece catalogue -----------------------------------------------------

    static let shapes: [PieceShape] = [
        PieceShape(id: "dot", cells: [GridPoint(0, 0)], weight: 4),

        PieceShape(id: "duo-h", cells: [GridPoint(0, 0), GridPoint(0, 1)], weight: 10),
        PieceShape(id: "duo-v", cells: [GridPoint(0, 0), GridPoint(1, 0)], weight: 10),

        PieceShape(id: "tri-h", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(0, 2)], weight: 8),
        PieceShape(id: "tri-v", cells: [GridPoint(0, 0), GridPoint(1, 0), GridPoint(2, 0)], weight: 8),
        PieceShape(id: "corner-a", cells: [GridPoint(0, 0), GridPoint(1, 0), GridPoint(1, 1)], weight: 7),
        PieceShape(id: "corner-b", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 1)], weight: 7),
        PieceShape(id: "corner-c", cells: [GridPoint(0, 1), GridPoint(1, 0), GridPoint(1, 1)], weight: 7),
        PieceShape(id: "corner-d", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 0)], weight: 7),

        PieceShape(id: "square", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 0), GridPoint(1, 1)], weight: 9),
        PieceShape(id: "quad-h", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(0, 2), GridPoint(0, 3)], weight: 4),
        PieceShape(id: "quad-v", cells: [GridPoint(0, 0), GridPoint(1, 0), GridPoint(2, 0), GridPoint(3, 0)], weight: 4),
        PieceShape(id: "tee", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(0, 2), GridPoint(1, 1)], weight: 5),
        PieceShape(id: "ell", cells: [GridPoint(0, 0), GridPoint(1, 0), GridPoint(2, 0), GridPoint(2, 1)], weight: 5),
        PieceShape(id: "jay", cells: [GridPoint(0, 1), GridPoint(1, 1), GridPoint(2, 1), GridPoint(2, 0)], weight: 5),
        PieceShape(id: "ess", cells: [GridPoint(0, 1), GridPoint(0, 2), GridPoint(1, 0), GridPoint(1, 1)], weight: 4),
        PieceShape(id: "zee", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 1), GridPoint(1, 2)], weight: 4),

        PieceShape(id: "penta-h", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(0, 2), GridPoint(0, 3), GridPoint(0, 4)], weight: 2),
        PieceShape(id: "penta-p", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 0), GridPoint(1, 1), GridPoint(2, 0)], weight: 3),
        PieceShape(id: "penta-t", cells: [GridPoint(0, 0), GridPoint(0, 1), GridPoint(0, 2), GridPoint(1, 1), GridPoint(2, 1)], weight: 2),
    ]

    static func shapes(minSize: Int, maxSize: Int) -> [PieceShape] {
        let pool = shapes.filter { $0.size >= minSize && $0.size <= maxSize }
        return pool.isEmpty ? shapes : pool
    }
}
