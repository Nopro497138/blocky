import Foundation

/// One candidate placement, scored.
struct MoveSuggestion {
    let trayIndex: Int
    let origin: GridPoint
    let color: BlockColor
    /// Cells the piece would occupy, ready to highlight.
    let cells: [GridPoint]
    /// Points the placement would score immediately.
    let immediateScore: Int
    let clearedCells: Int
    let biggestGroup: Int
    /// How much the largest same-colour cluster grows — the setup value.
    let clusterGain: Int
    let rating: Double

    var detonates: Bool { clearedCells > 0 }
}

/// Finds the best placement available right now.
///
/// It runs the real `CascadeResolver` on a copy of the board, so a hint can
/// never suggest something the game would score differently. Beyond immediate
/// points it values two things the player has to think about anyway: growing
/// the biggest single-colour cluster (size is what a blast pays for) and not
/// stranding empty cells that no piece can ever fill.
enum MoveEvaluator {

    /// Cost weights. Tuned to agree with the greedy policy in tools/simulate.js.
    private enum Weight {
        static let cleared = 8.0
        static let occupancy = -4.0
        static let deadSpace = -6.0
        static let clusterGain = 26.0
        static let biggestGroup = 12.0
        static let adjacency = 5.0
    }

    static func best(board: Board, tray: [Piece?], threshold: Int, feverMultiplier: Double) -> MoveSuggestion? {
        rank(board: board, tray: tray, threshold: threshold, feverMultiplier: feverMultiplier, limit: 1).first
    }

    /// Every legal placement, best first.
    static func rank(board: Board,
                     tray: [Piece?],
                     threshold: Int,
                     feverMultiplier: Double,
                     limit: Int = Int.max) -> [MoveSuggestion] {
        var suggestions: [MoveSuggestion] = []
        let clusterBefore = board.largestCluster

        for (index, piece) in tray.enumerated() {
            guard let piece = piece else { continue }
            for origin in board.placements(for: piece.shape) {
                var copy = board
                let cells = copy.place(piece, row: origin.row, col: origin.col)
                let adjacency = sameColorNeighbours(in: copy, cells: cells, color: piece.color)

                let steps = CascadeResolver.resolve(board: &copy,
                                                    startThreshold: threshold,
                                                    feverMultiplier: feverMultiplier)
                let score = steps.reduce(0) { $0 + $1.score }
                let cleared = steps.reduce(0) { $0 + $1.cellCount }
                let biggest = steps.reduce(0) { partial, step in
                    max(partial, step.groups.reduce(0) { max($0, $1.cells.count) })
                }
                let clusterAfter = copy.largestCluster
                let clusterGain = max(0, clusterAfter - clusterBefore)

                var rating = Double(score)
                rating += Double(cleared) * Weight.cleared
                rating += Double(copy.occupiedCount) * Weight.occupancy
                rating += Double(copy.deadSpace) * Weight.deadSpace
                rating += Double(clusterGain) * Weight.clusterGain
                rating += Double(biggest) * Weight.biggestGroup
                rating += Double(adjacency) * Weight.adjacency

                suggestions.append(MoveSuggestion(trayIndex: index,
                                                  origin: origin,
                                                  color: piece.color,
                                                  cells: cells,
                                                  immediateScore: score,
                                                  clearedCells: cleared,
                                                  biggestGroup: biggest,
                                                  clusterGain: clusterGain,
                                                  rating: rating))
            }
        }

        suggestions.sort { $0.rating > $1.rating }
        return limit >= suggestions.count ? suggestions : Array(suggestions.prefix(limit))
    }

    private static func sameColorNeighbours(in board: Board, cells: [GridPoint], color: BlockColor) -> Int {
        let placed = Set(cells)
        var count = 0
        for cell in cells {
            let neighbours = [GridPoint(cell.row - 1, cell.col), GridPoint(cell.row + 1, cell.col),
                              GridPoint(cell.row, cell.col - 1), GridPoint(cell.row, cell.col + 1)]
            for neighbour in neighbours where !placed.contains(neighbour) {
                if board.color(at: neighbour.row, neighbour.col) == color { count += 1 }
            }
        }
        return count
    }
}
