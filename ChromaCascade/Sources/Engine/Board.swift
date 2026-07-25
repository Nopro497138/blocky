import Foundation

/// The playfield. Cells hold a `BlockColor` raw value, 0 meaning empty.
///
/// Two rules matter and they are deliberately asymmetric:
///  * placing a piece does **not** move anything — the piece locks exactly where
///    the player dropped it, which is what preserves the 2D packing puzzle;
///  * a detonation *does* pull everything down its column, which is what creates
///    cascades. See DESIGN.md §2.
struct Board {

    let cols: Int
    let rows: Int
    private(set) var cells: [UInt8]

    init(cols: Int = GameConfig.cols, rows: Int = GameConfig.rows) {
        self.cols = cols
        self.rows = rows
        self.cells = [UInt8](repeating: 0, count: cols * rows)
    }

    // MARK: - Access

    func index(_ row: Int, _ col: Int) -> Int { row * cols + col }

    func contains(_ row: Int, _ col: Int) -> Bool {
        row >= 0 && row < rows && col >= 0 && col < cols
    }

    func color(at row: Int, _ col: Int) -> BlockColor? {
        guard contains(row, col) else { return nil }
        return BlockColor(rawValue: cells[index(row, col)])
    }

    func isEmpty(_ row: Int, _ col: Int) -> Bool {
        guard contains(row, col) else { return false }
        return cells[index(row, col)] == 0
    }

    var occupiedCount: Int {
        cells.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
    }

    /// Rows the stack currently reaches, measured from the bottom.
    var stackHeight: Int {
        for row in 0..<rows {
            for col in 0..<cols where cells[index(row, col)] != 0 {
                return rows - row
            }
        }
        return 0
    }

    mutating func clear() {
        cells = [UInt8](repeating: 0, count: cols * rows)
    }

    mutating func setColor(_ color: BlockColor?, at row: Int, _ col: Int) {
        guard contains(row, col) else { return }
        cells[index(row, col)] = color?.rawValue ?? 0
    }

    // MARK: - Placement

    /// True when every cell of `shape`, offset to (`row`, `col`), is on-board and free.
    func fits(_ shape: PieceShape, row: Int, col: Int) -> Bool {
        for cell in shape.cells {
            let r = cell.row + row
            let c = cell.col + col
            if !contains(r, c) { return false }
            if cells[index(r, c)] != 0 { return false }
        }
        return true
    }

    /// Every origin at which the shape fits, scanned top-left to bottom-right.
    func placements(for shape: PieceShape) -> [GridPoint] {
        var result: [GridPoint] = []
        let maxRow = rows - shape.height
        let maxCol = cols - shape.width
        guard maxRow >= 0 && maxCol >= 0 else { return result }
        for row in 0...maxRow {
            for col in 0...maxCol where fits(shape, row: row, col: col) {
                result.append(GridPoint(row, col))
            }
        }
        return result
    }

    func hasAnyPlacement(for shape: PieceShape) -> Bool {
        let maxRow = rows - shape.height
        let maxCol = cols - shape.width
        guard maxRow >= 0 && maxCol >= 0 else { return false }
        for row in 0...maxRow {
            for col in 0...maxCol where fits(shape, row: row, col: col) {
                return true
            }
        }
        return false
    }

    @discardableResult
    mutating func place(_ piece: Piece, row: Int, col: Int) -> [GridPoint] {
        var placed: [GridPoint] = []
        placed.reserveCapacity(piece.shape.cells.count)
        for cell in piece.shape.cells {
            let point = GridPoint(cell.row + row, cell.col + col)
            guard contains(point.row, point.col) else { continue }
            cells[index(point.row, point.col)] = piece.color.rawValue
            placed.append(point)
        }
        return placed
    }

    // MARK: - Groups

    /// All orthogonally connected same-colour groups of at least `minSize` cells.
    ///
    /// When `color` is given, groups of every other colour are ignored — that is
    /// what keeps a cascade inside the colour that started it.
    func groups(minSize: Int, color: BlockColor? = nil) -> [[GridPoint]] {
        var seen = [Bool](repeating: false, count: cells.count)
        var result: [[GridPoint]] = []
        var stack: [Int] = []

        for row in 0..<rows {
            for col in 0..<cols {
                let start = index(row, col)
                if seen[start] || cells[start] == 0 { continue }
                let cellColor = cells[start]

                var group: [Int] = []
                stack.removeAll(keepingCapacity: true)
                stack.append(start)
                seen[start] = true

                while let current = stack.popLast() {
                    group.append(current)
                    let r = current / cols
                    let c = current % cols
                    if r > 0 { visit(r - 1, c, cellColor, &seen, &stack) }
                    if r < rows - 1 { visit(r + 1, c, cellColor, &seen, &stack) }
                    if c > 0 { visit(r, c - 1, cellColor, &seen, &stack) }
                    if c < cols - 1 { visit(r, c + 1, cellColor, &seen, &stack) }
                }

                if group.count >= minSize, color == nil || color?.rawValue == cellColor {
                    result.append(group.map { GridPoint($0 / cols, $0 % cols) })
                }
            }
        }
        return result
    }

    private func visit(_ row: Int, _ col: Int, _ color: UInt8, _ seen: inout [Bool], _ stack: inout [Int]) {
        let i = index(row, col)
        if !seen[i] && cells[i] == color {
            seen[i] = true
            stack.append(i)
        }
    }

    /// The `count` colours the board currently holds most of, most common first.
    /// Fever uses this to narrow the tray to what the player has already built.
    func dominantColors(count: Int, from palette: [BlockColor]) -> [BlockColor] {
        var tally: [UInt8: Int] = [:]
        for value in cells where value != 0 {
            tally[value, default: 0] += 1
        }
        let ranked = palette.sorted { lhs, rhs in
            let left = tally[lhs.rawValue] ?? 0
            let right = tally[rhs.rawValue] ?? 0
            return left == right ? lhs.rawValue < rhs.rawValue : left > right
        }
        return Array(ranked.prefix(max(1, count)))
    }

    /// Size of the largest same-colour cluster on the board. The move evaluator
    /// rewards growing this, because size is what a blast now pays for.
    var largestCluster: Int {
        groups(minSize: 1).reduce(0) { max($0, $1.count) }
    }

    /// Empty cells with no empty orthogonal neighbour, weighted — the board's
    /// dead space, which is what eventually kills a run.
    var deadSpace: Int {
        var total = 0
        for row in 0..<rows {
            for col in 0..<cols where cells[index(row, col)] == 0 {
                var free = 0
                if row > 0 && cells[index(row - 1, col)] == 0 { free += 1 }
                if row < rows - 1 && cells[index(row + 1, col)] == 0 { free += 1 }
                if col > 0 && cells[index(row, col - 1)] == 0 { free += 1 }
                if col < cols - 1 && cells[index(row, col + 1)] == 0 { free += 1 }
                if free == 0 { total += 3 } else if free == 1 { total += 1 }
            }
        }
        return total
    }

    // MARK: - Mutation

    mutating func remove(_ points: [GridPoint]) {
        for point in points where contains(point.row, point.col) {
            cells[index(point.row, point.col)] = 0
        }
    }

    /// Compacts every column downwards and reports what moved, so the scene can
    /// animate the fall instead of snapping the board to its new state.
    mutating func applyGravity() -> [FallMove] {
        var moves: [FallMove] = []
        for col in 0..<cols {
            var writeRow = rows - 1
            var row = rows - 1
            while row >= 0 {
                let value = cells[index(row, col)]
                if value != 0 {
                    if writeRow != row {
                        cells[index(writeRow, col)] = value
                        cells[index(row, col)] = 0
                        if let color = BlockColor(rawValue: value) {
                            moves.append(FallMove(from: GridPoint(row, col),
                                                  to: GridPoint(writeRow, col),
                                                  color: color))
                        }
                    }
                    writeRow -= 1
                }
                row -= 1
            }
        }
        return moves
    }
}
