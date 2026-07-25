import Foundation

/// Runs a detonation cascade on a board.
///
/// Extracted from `GameEngine` so the move evaluator can simulate the exact
/// same rules on a copy of the board — a hint that used a different rule than
/// the game would be worse than no hint at all.
enum CascadeResolver {

    /// Score for one detonated group. The quadratic overshoot term is the whole
    /// reward curve: a single 20-cell blob is worth far more than four 5-cell
    /// ones, which is what makes building a big cluster the thing to aim for.
    static func groupScore(count: Int, threshold: Int) -> Int {
        let over = max(0, count - threshold)
        return 10 * count + GameConfig.sizeBonusFactor * over * over
    }

    static func chainMultiplier(_ step: Int) -> Double {
        let table = GameConfig.chainMultipliers
        return step < table.count ? table[step] : table[table.count - 1]
    }

    /// Detonates until the board is stable.
    ///
    /// - The opening rung needs `startThreshold` cells of one colour.
    /// - Follow-up rungs need `startThreshold - chainRelief` and, when
    ///   `monoColorChain` is on, must be the *same colour* as the opening rung.
    ///   Both restrictions exist because the alternative — cheap, any-colour
    ///   follow-ups — made one placement dissolve the whole board.
    static func resolve(board: inout Board,
                        startThreshold: Int,
                        feverMultiplier: Double,
                        bombCells: [GridPoint]? = nil) -> [CascadeStep] {
        var steps: [CascadeStep] = []
        var stepIndex = 0
        var chainColor: BlockColor?

        if let bombCells = bombCells, !bombCells.isEmpty {
            var byColor: [UInt8: [GridPoint]] = [:]
            for point in bombCells {
                if let color = board.color(at: point.row, point.col) {
                    byColor[color.rawValue, default: []].append(point)
                }
            }
            var groups: [DetonatedGroup] = []
            var raw = 0
            for value in byColor.keys.sorted() {
                guard let color = BlockColor(rawValue: value), let points = byColor[value] else { continue }
                let groupValue = 12 * points.count
                raw += groupValue
                groups.append(DetonatedGroup(cells: points, color: color, score: groupValue))
            }
            if !groups.isEmpty {
                board.remove(bombCells)
                let falls = board.applyGravity()
                steps.append(CascadeStep(index: 0,
                                         groups: groups,
                                         falls: falls,
                                         multiplier: feverMultiplier,
                                         score: Int((Double(raw) * feverMultiplier).rounded())))
                // A bomb is a tool, not a colour move, so it does not seed a
                // chain colour: whatever the debris forms may carry on.
            }
            stepIndex = 1
        }

        while steps.count < 64 {
            let threshold = stepIndex == 0
                ? startThreshold
                : max(2, startThreshold - GameConfig.chainRelief)
            let filter: BlockColor? = (GameConfig.monoColorChain && stepIndex > 0) ? chainColor : nil
            let found = board.groups(minSize: threshold, color: filter)
            if found.isEmpty { break }

            var groups: [DetonatedGroup] = []
            var rawScore = 0
            for cells in found {
                guard let first = cells.first,
                      let color = board.color(at: first.row, first.col) else { continue }
                if chainColor == nil { chainColor = color }
                let value = groupScore(count: cells.count, threshold: threshold)
                rawScore += value
                groups.append(DetonatedGroup(cells: cells, color: color, score: value))
                board.remove(cells)
            }
            if groups.isEmpty { break }

            let falls = board.applyGravity()
            let simultaneity = 1.0 + GameConfig.simultaneityBonus * Double(groups.count - 1)
            let multiplier = chainMultiplier(stepIndex) * simultaneity * feverMultiplier
            steps.append(CascadeStep(index: stepIndex,
                                     groups: groups,
                                     falls: falls,
                                     multiplier: multiplier,
                                     score: Int((Double(rawScore) * multiplier).rounded())))
            stepIndex += 1
        }

        return steps
    }
}
