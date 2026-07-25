import Foundation

// MARK: - Result types

enum PowerUp {
    case bomb
    case reroll
}

struct DetonatedGroup {
    let cells: [GridPoint]
    let color: BlockColor
    let score: Int
}

/// One rung of a cascade. The renderer plays these back in order, which is what
/// turns a single instantaneous board mutation into a rising, escalating show.
struct CascadeStep {
    let index: Int
    let groups: [DetonatedGroup]
    let falls: [FallMove]
    let multiplier: Double
    let score: Int

    var cellCount: Int { groups.reduce(0) { $0 + $1.cells.count } }
}

struct TurnResult {
    var placedCells: [GridPoint] = []
    var placedColor: BlockColor?
    var steps: [CascadeStep] = []
    var gainedScore: Int = 0
    var totalScore: Int = 0
    var streak: Int = 0
    var heat: Double = 0
    var feverStarted: Bool = false
    var feverEnded: Bool = false
    var isFever: Bool = false
    var stageAdvancedTo: Int?
    var trayRefilled: Bool = false
    var earnedPowerUps: [PowerUp] = []
    var isStuck: Bool = false
    var isGameOver: Bool = false
    /// Cells in the single largest group this turn — the headline number now.
    var biggestGroup: Int = 0

    var chainDepth: Int { steps.count }
    var clearedCells: Int { steps.reduce(0) { $0 + $1.cellCount } }
}

// MARK: - Engine

/// Pure game logic: no SpriteKit, no UIKit, fully deterministic for a given seed.
final class GameEngine {

    private(set) var board = Board()
    private(set) var tray: [Piece?] = [nil, nil, nil]
    private(set) var score = 0
    private(set) var turn = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var bestChain = 0
    private(set) var heat = 0.0
    private(set) var feverPlacementsLeft = 0
    private(set) var bombCharges = 0
    private(set) var rerollCharges = 0
    private(set) var isGameOver = false
    private(set) var totalBlasts = 0
    private(set) var biggestGroupEver = 0
    /// The two colours the tray is restricted to during fever, empty otherwise.
    private(set) var feverPalette: [BlockColor] = []
    private var lastHintTurn = -GameConfig.hintCooldown

    private var rng = SeededGenerator(seed: 1)
    private var serialCounter = 0
    private var nextBombScore = GameConfig.bombEveryPoints
    private var nextRerollScore = GameConfig.rerollEveryPoints

    var isFever: Bool { feverPlacementsLeft > 0 }
    var stageIndex: Int { GameConfig.stageIndex(forTurn: turn) }
    var stage: Stage { GameConfig.stages[stageIndex] }
    var heatFraction: Double { min(1.0, heat / GameConfig.feverHeatNeeded) }

    /// Cells a group needs right now to *start* a detonation.
    ///
    /// Fever deliberately does *not* lower this. Making blasts automatic during
    /// fever meant the board cleared itself and the player stopped mattering;
    /// fever now narrows the tray palette instead, so the reward is the chance
    /// to build one enormous cluster by hand.
    var activeThreshold: Int { stage.threshold }

    private var feverMultiplier: Double {
        isFever ? GameConfig.feverScoreMultiplier : 1.0
    }

    // MARK: - Lifecycle

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        startNewGame(seed: seed)
    }

    func startNewGame(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        rng = SeededGenerator(seed: seed)
        board.clear()
        score = 0
        turn = 0
        streak = 0
        bestStreak = 0
        bestChain = 0
        heat = 0
        feverPlacementsLeft = 0
        bombCharges = 0
        rerollCharges = 0
        isGameOver = false
        totalBlasts = 0
        biggestGroupEver = 0
        feverPalette = []
        lastHintTurn = -GameConfig.hintCooldown
        serialCounter = 0
        nextBombScore = GameConfig.bombEveryPoints
        nextRerollScore = GameConfig.rerollEveryPoints
        tray = [nil, nil, nil]
        refillTray()
    }

    // MARK: - Tray

    private func makePiece(for stage: Stage) -> Piece {
        let pool = GameConfig.shapes(minSize: stage.minPiece, maxSize: stage.maxPiece)
        let totalWeight = pool.reduce(0) { $0 + $1.weight }
        var roll = rng.int(below: max(1, totalWeight))
        var chosen = pool[pool.count - 1]
        for shape in pool {
            roll -= shape.weight
            if roll < 0 {
                chosen = shape
                break
            }
        }
        let stagePalette = BlockColor.palette(count: stage.colors)
        let palette = feverPalette.isEmpty ? stagePalette : feverPalette
        let color = palette[rng.int(below: palette.count)]
        serialCounter += 1
        return Piece(shape: chosen, color: color, serial: serialCounter)
    }

    private func refillTray() {
        let stage = GameConfig.stage(forTurn: turn)
        for i in 0..<tray.count {
            tray[i] = makePiece(for: stage)
        }
    }

    var trayIsEmpty: Bool {
        tray.allSatisfy { $0 == nil }
    }

    /// True when at least one piece still in the tray fits somewhere.
    var hasLegalMove: Bool {
        for case let piece? in tray where board.hasAnyPlacement(for: piece.shape) {
            return true
        }
        return false
    }

    func canPlace(trayIndex: Int, row: Int, col: Int) -> Bool {
        guard tray.indices.contains(trayIndex), let piece = tray[trayIndex] else { return false }
        return board.fits(piece.shape, row: row, col: col)
    }

    // MARK: - Cascade

    private func runCascade(startThreshold: Int, bombCells: [GridPoint]?) -> [CascadeStep] {
        CascadeResolver.resolve(board: &board,
                                startThreshold: startThreshold,
                                feverMultiplier: feverMultiplier,
                                bombCells: bombCells)
    }

    // MARK: - Turns

    func place(trayIndex: Int, row: Int, col: Int) -> TurnResult? {
        guard !isGameOver,
              tray.indices.contains(trayIndex),
              let piece = tray[trayIndex],
              board.fits(piece.shape, row: row, col: col) else { return nil }

        let stageBefore = stageIndex
        let threshold = activeThreshold

        var result = TurnResult()
        result.placedColor = piece.color
        result.placedCells = board.place(piece, row: row, col: col)
        tray[trayIndex] = nil

        result.steps = runCascade(startThreshold: threshold, bombCells: nil)
        finishTurn(&result, stageBefore: stageBefore)
        return result
    }

    /// Consumes a bomb charge and blows a 3×3 hole, which then cascades normally.
    func useBomb(row: Int, col: Int) -> TurnResult? {
        guard !isGameOver, bombCharges > 0 else { return nil }

        var cells: [GridPoint] = []
        for r in (row - 1)...(row + 1) {
            for c in (col - 1)...(col + 1) where board.contains(r, c) && !board.isEmpty(r, c) {
                cells.append(GridPoint(r, c))
            }
        }
        guard !cells.isEmpty else { return nil }

        bombCharges -= 1
        let stageBefore = stageIndex

        var result = TurnResult()
        result.steps = runCascade(startThreshold: activeThreshold, bombCells: cells)
        finishTurn(&result, stageBefore: stageBefore, countsAsPlacement: false)
        return result
    }

    // MARK: - Hints

    /// True when a hint may be requested again.
    var hintAvailable: Bool {
        !isGameOver && turn - lastHintTurn >= GameConfig.hintCooldown
    }

    var turnsUntilHint: Int {
        max(0, GameConfig.hintCooldown - (turn - lastHintTurn))
    }

    /// The strongest placement on the board right now, or nil if nothing fits.
    ///
    /// Deliberately rate-limited: an always-on perfect suggestion would play the
    /// game for the player. It is meant for the moment you cannot see a way out.
    func requestHint() -> MoveSuggestion? {
        guard hintAvailable else { return nil }
        let suggestion = MoveEvaluator.best(board: board,
                                            tray: tray,
                                            threshold: activeThreshold,
                                            feverMultiplier: feverMultiplier)
        if suggestion != nil { lastHintTurn = turn }
        return suggestion
    }

    /// Used by the demo/autoplay driver; never rate-limited.
    func bestMove() -> MoveSuggestion? {
        MoveEvaluator.best(board: board,
                           tray: tray,
                           threshold: activeThreshold,
                           feverMultiplier: feverMultiplier)
    }

    /// Consumes a reroll charge and replaces the whole tray.
    func useReroll() -> Bool {
        guard !isGameOver, rerollCharges > 0 else { return false }
        rerollCharges -= 1
        refillTray()
        isGameOver = !hasLegalMove && bombCharges == 0 && rerollCharges == 0
        return true
    }

    /// Shared bookkeeping: streak, heat, fever, stage, power-ups, game over.
    private func finishTurn(_ result: inout TurnResult, stageBefore: Int, countsAsPlacement: Bool = true) {
        let chainDepth = result.steps.count
        let wasFever = isFever

        for step in result.steps {
            result.gainedScore += step.score
        }
        score += result.gainedScore

        for step in result.steps {
            for group in step.groups where group.cells.count > result.biggestGroup {
                result.biggestGroup = group.cells.count
            }
        }
        biggestGroupEver = max(biggestGroupEver, result.biggestGroup)

        if chainDepth > 0 {
            totalBlasts += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            bestChain = max(bestChain, chainDepth)
            heat += 1.0 + Double(chainDepth)
            if feverPlacementsLeft > 0 {
                feverPlacementsLeft += GameConfig.feverExtendPerBlast
            }
        } else if countsAsPlacement {
            streak = 0
            heat = max(0, heat - GameConfig.feverHeatDrain)
        }

        if countsAsPlacement {
            if feverPlacementsLeft > 0 {
                feverPlacementsLeft -= 1
                if feverPlacementsLeft == 0 {
                    heat = GameConfig.feverHeatAfter
                    feverPalette = []
                    result.feverEnded = true
                }
            } else if heat >= GameConfig.feverHeatNeeded {
                feverPlacementsLeft = GameConfig.feverPlacements
                heat = 0
                // Fever hands over the colours the board already holds most of,
                // so it reads as "finish what you started" rather than as free
                // demolition.
                feverPalette = board.dominantColors(count: GameConfig.feverPaletteSize,
                                                    from: BlockColor.palette(count: stage.colors))
                result.feverStarted = true
            }
            turn += 1
        } else if wasFever && feverPlacementsLeft == 0 {
            result.feverEnded = true
        }

        while score >= nextBombScore && bombCharges < GameConfig.maxCharges {
            bombCharges += 1
            nextBombScore += GameConfig.bombEveryPoints
            result.earnedPowerUps.append(.bomb)
        }
        if score >= nextBombScore { nextBombScore = score + GameConfig.bombEveryPoints }

        while score >= nextRerollScore && rerollCharges < GameConfig.maxCharges {
            rerollCharges += 1
            nextRerollScore += GameConfig.rerollEveryPoints
            result.earnedPowerUps.append(.reroll)
        }
        if score >= nextRerollScore { nextRerollScore = score + GameConfig.rerollEveryPoints }

        if trayIsEmpty {
            refillTray()
            result.trayRefilled = true
        }

        let stageAfter = stageIndex
        if stageAfter != stageBefore {
            result.stageAdvancedTo = stageAfter
        }

        result.totalScore = score
        result.streak = streak
        result.heat = heat
        result.isFever = isFever

        // Running out of room is only fatal once the player has no way out. A
        // stored power-up buys one more chance, which is a better beat than a
        // sudden loss.
        let stuck = !hasLegalMove
        result.isStuck = stuck
        if stuck && bombCharges == 0 && rerollCharges == 0 {
            isGameOver = true
        }
        result.isGameOver = isGameOver
    }
}
