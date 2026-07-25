import SpriteKit

/// Renders the playfield. Its own coordinate space has (0, 0) at the bottom-left
/// corner of the grid, so cell maths stays readable.
final class BoardNode: SKNode {

    let cols: Int
    let rows: Int
    let cellSize: CGFloat

    private var blocks: [SKSpriteNode?]
    private let cellLayer = SKNode()
    private let ghostLayer = SKNode()
    private let hintLayer = SKNode()
    private var dangerLine: SKShapeNode!
    private var frameNode: SKShapeNode!

    var boardSize: CGSize {
        CGSize(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }

    init(cols: Int, rows: Int, cellSize: CGFloat) {
        self.cols = cols
        self.rows = rows
        self.cellSize = cellSize
        self.blocks = [SKSpriteNode?](repeating: nil, count: cols * rows)
        super.init()
        buildBackground()
        addChild(cellLayer)
        addChild(ghostLayer)
        addChild(hintLayer)
        cellLayer.zPosition = 10
        ghostLayer.zPosition = 8
        hintLayer.zPosition = 9
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Geometry

    func position(row: Int, col: Int) -> CGPoint {
        CGPoint(x: (CGFloat(col) + 0.5) * cellSize,
                y: (CGFloat(rows - row) - 0.5) * cellSize)
    }

    /// Nearest grid cell for a point in this node's space (may be out of bounds).
    func gridPoint(for point: CGPoint) -> GridPoint {
        let col = Int(floor(point.x / cellSize))
        let row = rows - 1 - Int(floor(point.y / cellSize))
        return GridPoint(row, col)
    }

    func contains(point: CGPoint, slack: CGFloat = 0) -> Bool {
        let size = boardSize
        return point.x >= -slack && point.x <= size.width + slack
            && point.y >= -slack && point.y <= size.height + slack
    }

    // MARK: - Background

    private func buildBackground() {
        let size = boardSize
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)

        frameNode = SKShapeNode(rect: rect.insetBy(dx: -cellSize * 0.16, dy: -cellSize * 0.16),
                                cornerRadius: cellSize * 0.42)
        frameNode.fillColor = Theme.boardFill
        frameNode.strokeColor = Theme.boardStroke
        frameNode.lineWidth = 2
        frameNode.glowWidth = 1.5
        frameNode.zPosition = 0
        addChild(frameNode)

        let slot = BlockTextureFactory.shared.slotTexture(size: cellSize)
        for row in 0..<rows {
            for col in 0..<cols {
                let node = SKSpriteNode(texture: slot)
                node.size = CGSize(width: cellSize, height: cellSize)
                node.position = position(row: row, col: col)
                node.zPosition = 1
                addChild(node)
            }
        }

        let dangerY = (CGFloat(rows - GameConfig.dangerRows)) * cellSize
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: dangerY))
        path.addLine(to: CGPoint(x: size.width, y: dangerY))
        dangerLine = SKShapeNode(path: path)
        dangerLine.strokeColor = Theme.dangerColor
        dangerLine.lineWidth = 2
        dangerLine.glowWidth = 3
        dangerLine.alpha = 0
        dangerLine.zPosition = 5
        addChild(dangerLine)
    }

    // MARK: - Blocks

    private func index(_ row: Int, _ col: Int) -> Int { row * cols + col }

    func block(at point: GridPoint) -> SKSpriteNode? {
        guard point.row >= 0, point.row < rows, point.col >= 0, point.col < cols else { return nil }
        return blocks[index(point.row, point.col)]
    }

    @discardableResult
    func addBlock(color: BlockColor, at point: GridPoint) -> SKSpriteNode {
        removeBlock(at: point)
        let node = SKSpriteNode(texture: BlockTextureFactory.shared.texture(for: color, size: cellSize))
        node.size = CGSize(width: cellSize, height: cellSize)
        node.position = position(row: point.row, col: point.col)
        cellLayer.addChild(node)
        blocks[index(point.row, point.col)] = node
        return node
    }

    func removeBlock(at point: GridPoint) {
        guard point.row >= 0, point.row < rows, point.col >= 0, point.col < cols else { return }
        blocks[index(point.row, point.col)]?.removeFromParent()
        blocks[index(point.row, point.col)] = nil
    }

    /// Detaches the node without destroying it (used before an explosion animation).
    func detachBlock(at point: GridPoint) -> SKSpriteNode? {
        guard point.row >= 0, point.row < rows, point.col >= 0, point.col < cols else { return nil }
        let node = blocks[index(point.row, point.col)]
        blocks[index(point.row, point.col)] = nil
        return node
    }

    func moveBlock(from: GridPoint, to: GridPoint, duration: TimeInterval) {
        guard let node = block(at: from) else { return }
        blocks[index(from.row, from.col)] = nil
        blocks[index(to.row, to.col)]?.removeFromParent()
        blocks[index(to.row, to.col)] = node
        let target = position(row: to.row, col: to.col)
        let drop = SKAction.move(to: target, duration: duration)
        drop.timingMode = .easeIn
        node.run(.sequence([
            drop,
            .scaleY(to: 0.82, duration: 0.05),
            .scaleY(to: 1.0, duration: 0.08),
        ]))
    }

    func clearAllBlocks() {
        for node in blocks where node != nil {
            node?.removeFromParent()
        }
        blocks = [SKSpriteNode?](repeating: nil, count: cols * rows)
    }

    /// Rebuilds the visual grid from an engine board (used on new game / restore).
    func sync(with board: Board) {
        clearAllBlocks()
        for row in 0..<rows {
            for col in 0..<cols {
                if let color = board.color(at: row, col) {
                    addBlock(color: color, at: GridPoint(row, col))
                }
            }
        }
    }

    // MARK: - Ghost

    /// Preview of where the dragged piece would lock in. Only ever shown for a
    /// legal drop — an illegal one simply has no ghost, which reads faster than
    /// a "forbidden" colour.
    func showGhost(cells: [GridPoint], color: BlockColor) {
        ghostLayer.removeAllChildren()
        let texture = BlockTextureFactory.shared.ghostTexture(size: cellSize, color: color)
        for cell in cells {
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: cellSize, height: cellSize)
            node.position = position(row: cell.row, col: cell.col)
            ghostLayer.addChild(node)
        }
        if ghostLayer.action(forKey: "pulse") == nil {
            ghostLayer.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.32),
                .fadeAlpha(to: 1.0, duration: 0.32),
            ])), withKey: "pulse")
        }
    }

    // MARK: - Hint

    /// Marks the placement the evaluator recommends. Drawn as an outline rather
    /// than a filled ghost so it cannot be confused with the piece being dragged.
    func showHint(cells: [GridPoint], color: BlockColor, duration: TimeInterval = 4.0) {
        hideHint()
        let tint = Theme.color(for: color)
        for cell in cells {
            let rect = CGRect(x: -cellSize / 2 + cellSize * 0.08,
                              y: -cellSize / 2 + cellSize * 0.08,
                              width: cellSize * 0.84, height: cellSize * 0.84)
            let node = SKShapeNode(rect: rect, cornerRadius: cellSize * 0.2)
            node.strokeColor = tint
            node.lineWidth = 3
            node.glowWidth = 3
            node.fillColor = tint.withAlphaComponent(0.14)
            node.position = position(row: cell.row, col: cell.col)
            hintLayer.addChild(node)
        }
        hintLayer.alpha = 0
        hintLayer.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .repeat(.sequence([.fadeAlpha(to: 0.45, duration: 0.4),
                               .fadeAlpha(to: 1.0, duration: 0.4)]),
                    count: max(1, Int(duration / 0.8))),
            .fadeOut(withDuration: 0.3),
            .run { [weak self] in self?.hintLayer.removeAllChildren() },
        ]))
    }

    func hideHint() {
        hintLayer.removeAllActions()
        hintLayer.removeAllChildren()
        hintLayer.alpha = 1
    }

    func hideGhost() {
        ghostLayer.removeAllActions()
        ghostLayer.removeAllChildren()
        ghostLayer.alpha = 1
    }

    // MARK: - States

    func setDanger(_ active: Bool) {
        if active {
            guard dangerLine.action(forKey: "danger") == nil else { return }
            dangerLine.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.9, duration: 0.45),
                .fadeAlpha(to: 0.25, duration: 0.45),
            ])), withKey: "danger")
        } else {
            dangerLine.removeAction(forKey: "danger")
            dangerLine.run(.fadeOut(withDuration: 0.25))
        }
    }

    func setFever(_ active: Bool) {
        frameNode.removeAction(forKey: "fever")
        if active {
            frameNode.run(.repeatForever(.sequence([
                .run { [weak self] in self?.frameNode.strokeColor = Theme.feverA },
                .wait(forDuration: 0.22),
                .run { [weak self] in self?.frameNode.strokeColor = Theme.feverB },
                .wait(forDuration: 0.22),
            ])), withKey: "fever")
            frameNode.lineWidth = 3
            frameNode.glowWidth = 5
        } else {
            frameNode.strokeColor = Theme.boardStroke
            frameNode.lineWidth = 2
            frameNode.glowWidth = 1.5
        }
    }
}
