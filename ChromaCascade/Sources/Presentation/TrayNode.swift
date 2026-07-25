import SpriteKit

/// A piece drawn as blocks. Its position is the centre of the piece's (0, 0) cell,
/// which keeps the drag maths simple.
final class PieceNode: SKNode {

    let piece: Piece
    let cellSize: CGFloat

    var pieceWidth: CGFloat { CGFloat(piece.shape.width) * cellSize }
    var pieceHeight: CGFloat { CGFloat(piece.shape.height) * cellSize }

    init(piece: Piece, cellSize: CGFloat) {
        self.piece = piece
        self.cellSize = cellSize
        super.init()
        let texture = BlockTextureFactory.shared.texture(for: piece.color, size: cellSize)
        for cell in piece.shape.cells {
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: cellSize, height: cellSize)
            node.position = CGPoint(x: CGFloat(cell.col) * cellSize,
                                    y: -CGFloat(cell.row) * cellSize)
            addChild(node)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Offset from the node's position to the visual centre of the piece.
    var centerOffset: CGPoint {
        CGPoint(x: (pieceWidth - cellSize) / 2, y: -(pieceHeight - cellSize) / 2)
    }
}

/// The three-slot piece tray at the bottom of the screen.
final class TrayNode: SKNode {

    let slotCount = 3
    let slotWidth: CGFloat
    let slotHeight: CGFloat
    let boardCellSize: CGFloat

    private var slotNodes: [SKShapeNode] = []
    private var pieceNodes: [PieceNode?] = []

    /// Pieces are drawn smaller than board cells so a 5-cell piece still fits.
    private var trayCellSize: CGFloat { boardCellSize * 0.62 }

    init(width: CGFloat, height: CGFloat, boardCellSize: CGFloat) {
        self.slotWidth = width / 3
        self.slotHeight = height
        self.boardCellSize = boardCellSize
        super.init()
        pieceNodes = [PieceNode?](repeating: nil, count: slotCount)
        for i in 0..<slotCount {
            let rect = CGRect(x: -slotWidth / 2 + 4, y: -slotHeight / 2 + 2,
                              width: slotWidth - 8, height: slotHeight - 4)
            let slot = SKShapeNode(rect: rect, cornerRadius: 14)
            slot.fillColor = UIColor(white: 1.0, alpha: 0.03)
            slot.strokeColor = UIColor(white: 1.0, alpha: 0.06)
            slot.lineWidth = 1
            slot.position = slotCenter(i)
            addChild(slot)
            slotNodes.append(slot)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Centre of a slot in tray-node space. Slot 0 is leftmost; the tray's own
    /// origin is its horizontal centre.
    func slotCenter(_ index: Int) -> CGPoint {
        CGPoint(x: (CGFloat(index) - 1) * slotWidth, y: 0)
    }

    func slotIndex(at point: CGPoint) -> Int? {
        for i in 0..<slotCount {
            let center = slotCenter(i)
            if abs(point.x - center.x) <= slotWidth / 2 && abs(point.y - center.y) <= slotHeight / 2 {
                return i
            }
        }
        return nil
    }

    func piece(at index: Int) -> Piece? {
        guard pieceNodes.indices.contains(index) else { return nil }
        return pieceNodes[index]?.piece
    }

    func setPieces(_ pieces: [Piece?], animated: Bool) {
        for i in 0..<slotCount {
            pieceNodes[i]?.removeFromParent()
            pieceNodes[i] = nil
            guard pieces.indices.contains(i), let piece = pieces[i] else { continue }

            let node = PieceNode(piece: piece, cellSize: trayCellSize)
            let center = slotCenter(i)
            node.position = CGPoint(x: center.x - node.centerOffset.x,
                                    y: center.y - node.centerOffset.y)
            addChild(node)
            pieceNodes[i] = node

            if animated {
                node.setScale(0.2)
                node.alpha = 0
                node.run(.sequence([
                    .wait(forDuration: 0.06 * Double(i)),
                    .group([.scale(to: 1.08, duration: 0.16), .fadeIn(withDuration: 0.12)]),
                    .scale(to: 1.0, duration: 0.08),
                ]))
            }
        }
    }

    func removePiece(at index: Int) {
        guard pieceNodes.indices.contains(index) else { return }
        pieceNodes[index]?.removeFromParent()
        pieceNodes[index] = nil
    }

    func setPieceHidden(_ hidden: Bool, at index: Int) {
        guard pieceNodes.indices.contains(index) else { return }
        pieceNodes[index]?.isHidden = hidden
    }

    /// Nudges pieces that no longer fit anywhere, so a dead end is visible.
    func markUnplayable(_ indices: Set<Int>) {
        for i in 0..<slotCount {
            guard let node = pieceNodes[i] else { continue }
            let dead = indices.contains(i)
            node.alpha = dead ? 0.32 : 1.0
            if dead && node.action(forKey: "dead") == nil {
                node.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.2, duration: 0.5),
                    .fadeAlpha(to: 0.42, duration: 0.5),
                ])), withKey: "dead")
            } else if !dead {
                node.removeAction(forKey: "dead")
                node.alpha = 1.0
            }
        }
    }

    /// Draws attention to the piece a hint refers to.
    func pulsePiece(at index: Int) {
        guard pieceNodes.indices.contains(index), let node = pieceNodes[index] else { return }
        node.removeAction(forKey: "hint")
        node.run(.repeat(.sequence([
            .scale(to: 1.18, duration: 0.22),
            .scale(to: 1.0, duration: 0.22),
        ]), count: 6), withKey: "hint")
    }

    func highlightSlot(_ index: Int, on: Bool) {
        guard slotNodes.indices.contains(index) else { return }
        slotNodes[index].strokeColor = on ? Theme.accent.withAlphaComponent(0.7)
                                          : UIColor(white: 1.0, alpha: 0.06)
    }
}
