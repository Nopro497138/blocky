import SpriteKit
import UIKit

final class GameScene: SKScene {

    // MARK: - State

    private enum InputState: Equatable {
        case idle
        case dragging
        case animating
        case bombTargeting
        case paused
        case gameOver
    }

    private let engine = GameEngine()
    private var state: InputState = .idle

    // Layers
    private let cameraNode = SKCameraNode()   // shake and punch live here
    private let worldNode = SKNode()          // all gameplay content
    private let fxLayer = SKNode()            // particles, popups, banners
    private let overlayLayer = SKNode()       // pause / game over
    private var backgroundNode: SKSpriteNode!
    private var feverWash: SKSpriteNode!
    private var dangerVignette: SKSpriteNode!

    // Content
    private var boardNode: BoardNode!
    private var trayNode: TrayNode!
    private var hudNode: HUDNode!
    private var bombButton: PillButton!
    private var rerollButton: PillButton!
    private var hintButton: PillButton!
    private var pauseButton: PillButton!
    private var hintLabel: SKLabelNode!

    // Drag
    private var dragTouch: UITouch?
    private var dragIndex: Int?
    private var dragNode: PieceNode?
    private var dragTarget: GridPoint?

    private var cellSize: CGFloat = 40
    private var safeTop: CGFloat = 0
    private var safeBottom: CGFloat = 0

    /// Duration of one cascade rung. Long enough to read, short enough to stay punchy.
    private let stepDuration: TimeInterval = 0.38

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Theme.backgroundTop
        scaleMode = .resizeFill
        anchorPoint = .zero

        safeTop = view.safeAreaInsets.top
        safeBottom = view.safeAreaInsets.bottom

        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode

        addChild(worldNode)
        worldNode.addChild(fxLayer)
        fxLayer.zPosition = 100
        addChild(overlayLayer)
        overlayLayer.zPosition = 500

        buildBackground()
        buildLayout()

        AudioManager.shared.configure()
        AudioManager.shared.startMusic()
        Haptics.shared.prepare()

        if let seed = DebugOptions.seed {
            engine.startNewGame(seed: seed)
        }

        refreshAll(animated: false)
        showOpeningHint()

        let moves = DebugOptions.autoplayMoves
        if moves > 0 {
            schedule(1.0) { [weak self] in self?.autoplayStep(remaining: moves) }
        }
    }

    override func willMove(from view: SKView) {
        AudioManager.shared.setFever(false)
    }

    // MARK: - Layout

    private func buildBackground() {
        backgroundNode = SKSpriteNode(texture: BlockTextureFactory.shared.verticalGradient(
            size: CGSize(width: 64, height: 128),
            top: Theme.backgroundBottom,
            bottom: Theme.backgroundTop))
        backgroundNode.anchorPoint = .zero
        backgroundNode.size = size
        backgroundNode.zPosition = -100
        addChild(backgroundNode)

        // A slow drifting glow keeps the empty background alive.
        for (index, color) in [Theme.feverA, Theme.accent, Theme.feverB].enumerated() {
            let glow = SKSpriteNode(texture: BlockTextureFactory.shared.radialGlow(diameter: 256, color: color))
            glow.size = CGSize(width: size.width * 1.3, height: size.width * 1.3)
            glow.alpha = 0.10
            glow.blendMode = .add
            glow.zPosition = -99
            glow.position = CGPoint(x: size.width * (index == 1 ? 0.8 : 0.2),
                                    y: size.height * (0.25 + 0.3 * CGFloat(index)))
            let drift = SKAction.sequence([
                .moveBy(x: 0, y: 60, duration: 6 + Double(index)),
                .moveBy(x: 0, y: -60, duration: 6 + Double(index)),
            ])
            glow.run(.repeatForever(drift))
            addChild(glow)
        }

        feverWash = SKSpriteNode(texture: BlockTextureFactory.shared.verticalGradient(
            size: CGSize(width: 64, height: 128),
            top: Theme.feverA,
            bottom: Theme.feverB))
        feverWash.anchorPoint = .zero
        feverWash.size = size
        feverWash.blendMode = .add
        feverWash.alpha = 0
        feverWash.zPosition = -98
        addChild(feverWash)

        dangerVignette = SKSpriteNode(texture: BlockTextureFactory.shared.radialGlow(diameter: 256, color: Theme.dangerColor))
        dangerVignette.size = CGSize(width: size.width * 2.2, height: size.height * 1.4)
        dangerVignette.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dangerVignette.blendMode = .add
        dangerVignette.alpha = 0
        dangerVignette.zPosition = 300
        addChild(dangerVignette)
    }

    private func buildLayout() {
        let margin: CGFloat = 14
        let hudHeight: CGFloat = 132
        let powerHeight: CGFloat = 46
        let trayHeight: CGFloat = min(112, size.height * 0.13)
        let gaps: CGFloat = 44

        let usableHeight = size.height - safeTop - safeBottom - hudHeight - powerHeight - trayHeight - gaps
        let cellFromHeight = usableHeight / CGFloat(GameConfig.rows)
        let cellFromWidth = (size.width - margin * 2) / CGFloat(GameConfig.cols)
        cellSize = floor(max(18, min(cellFromHeight, cellFromWidth)))

        hudNode = HUDNode(width: size.width - margin * 2)
        hudNode.position = CGPoint(x: size.width / 2, y: size.height - safeTop - 62)
        hudNode.zPosition = 10
        worldNode.addChild(hudNode)

        boardNode = BoardNode(cols: GameConfig.cols, rows: GameConfig.rows, cellSize: cellSize)
        let boardWidth = CGFloat(GameConfig.cols) * cellSize
        let boardHeight = CGFloat(GameConfig.rows) * cellSize
        let boardTop = hudNode.position.y + hudNode.bottomY - 14
        boardNode.position = CGPoint(x: (size.width - boardWidth) / 2, y: boardTop - boardHeight)
        boardNode.zPosition = 5
        worldNode.addChild(boardNode)

        let powerY = boardNode.position.y - 12 - powerHeight / 2
        let gap: CGFloat = 8
        let buttonWidth = (size.width - margin * 2 - gap * 2) / 3
        let firstX = margin + buttonWidth / 2

        hintButton = PillButton(title: "HINT", width: buttonWidth, height: powerHeight,
                                tint: Theme.positive, fontSize: 16, identifier: "btn.hint")
        hintButton.position = CGPoint(x: firstX, y: powerY)
        hintButton.zPosition = 10
        worldNode.addChild(hintButton)

        bombButton = PillButton(title: "BOMB", width: buttonWidth, height: powerHeight,
                                tint: Theme.feverA, fontSize: 16, identifier: "btn.bomb")
        bombButton.position = CGPoint(x: firstX + buttonWidth + gap, y: powerY)
        bombButton.zPosition = 10
        worldNode.addChild(bombButton)

        rerollButton = PillButton(title: "REROLL", width: buttonWidth, height: powerHeight,
                                  tint: Theme.accent, fontSize: 16, identifier: "btn.reroll")
        rerollButton.position = CGPoint(x: firstX + (buttonWidth + gap) * 2, y: powerY)
        rerollButton.zPosition = 10
        worldNode.addChild(rerollButton)

        let trayY = powerY - powerHeight / 2 - 10 - trayHeight / 2
        trayNode = TrayNode(width: size.width - margin * 2, height: trayHeight, boardCellSize: cellSize)
        trayNode.position = CGPoint(x: size.width / 2, y: max(safeBottom + trayHeight / 2 + 4, trayY))
        trayNode.zPosition = 10
        worldNode.addChild(trayNode)

        pauseButton = PillButton(title: "II", width: 44, height: 32, tint: Theme.textSecondary,
                                 fontSize: 15, identifier: "btn.pause")
        pauseButton.position = CGPoint(x: size.width - margin - 22, y: size.height - safeTop - 18)
        pauseButton.zPosition = 20
        worldNode.addChild(pauseButton)

        hintLabel = SKLabelNode(fontNamed: Theme.fontBold)
        hintLabel.fontSize = 14
        hintLabel.fontColor = Theme.textSecondary
        hintLabel.horizontalAlignmentMode = .center
        hintLabel.verticalAlignmentMode = .center
        hintLabel.position = CGPoint(x: size.width / 2, y: boardNode.position.y - 4)
        hintLabel.alpha = 0
        hintLabel.zPosition = 30
        worldNode.addChild(hintLabel)
    }

    private func showOpeningHint() {
        guard !Storage.seenTutorial else { return }
        Storage.seenTutorial = true
        showHintLabel("Drag blocks in. Connect \(engine.stage.threshold)+ of ONE colour to blast.", duration: 4.5)
    }

    private func showHintLabel(_ text: String, duration: TimeInterval = 2.2) {
        hintLabel.text = text
        hintLabel.removeAllActions()
        hintLabel.run(.sequence([
            .fadeAlpha(to: 1.0, duration: 0.25),
            .wait(forDuration: duration),
            .fadeAlpha(to: 0, duration: 0.4),
        ]))
    }

    // MARK: - Refresh

    private func refreshAll(animated: Bool) {
        boardNode.sync(with: engine.board)
        trayNode.setPieces(engine.tray, animated: animated)
        hudNode.setScore(engine.score, animated: false)
        hudNode.setBest(Storage.highScore)
        hudNode.setStage(engine.stage, index: engine.stageIndex)
        hudNode.setHeat(engine.heatFraction, isFever: engine.isFever)
        hudNode.setStreak(engine.streak)
        hudNode.setFeverActive(engine.isFever)
        bombButton.stopPulse()
        rerollButton.stopPulse()
        boardNode.hideHint()
        updatePowerButtons()
        updateDanger()
        updateUnplayableHints()
    }

    private func updatePowerButtons() {
        bombButton.setBadge(engine.bombCharges)
        bombButton.setEnabled(engine.bombCharges > 0)
        rerollButton.setBadge(engine.rerollCharges)
        rerollButton.setEnabled(engine.rerollCharges > 0)
        hintButton.setEnabled(engine.hintAvailable)
        hintButton.setTitle(engine.hintAvailable ? "HINT" : "HINT \(engine.turnsUntilHint)")
        if state != .bombTargeting { bombButton.setActive(false) }
    }

    private func updateDanger() {
        let danger = engine.board.stackHeight >= GameConfig.rows - GameConfig.dangerRows
        boardNode.setDanger(danger)
        dangerVignette.removeAction(forKey: "danger")
        if danger {
            dangerVignette.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.20, duration: 0.6),
                .fadeAlpha(to: 0.05, duration: 0.6),
            ])), withKey: "danger")
        } else {
            dangerVignette.run(.fadeAlpha(to: 0, duration: 0.3))
        }
    }

    /// Dims tray pieces that no longer fit anywhere, so a dead end is readable.
    private func updateUnplayableHints() {
        var dead: Set<Int> = []
        for (index, piece) in engine.tray.enumerated() {
            if let piece = piece, !engine.board.hasAnyPlacement(for: piece.shape) {
                dead.insert(index)
            }
        }
        trayNode.markUnplayable(dead)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)

        if let button = buttonName(at: point) {
            handleButton(button)
            return
        }

        switch state {
        case .gameOver, .paused, .animating:
            return
        case .bombTargeting:
            let boardPoint = boardNode.convert(point, from: self)
            let cell = boardNode.gridPoint(for: boardPoint)
            fireBomb(at: cell)
            return
        case .idle, .dragging:
            let trayPoint = trayNode.convert(point, from: self)
            guard let index = trayNode.slotIndex(at: trayPoint),
                  let piece = engine.tray[index] else { return }
            beginDrag(piece: piece, index: index, touch: touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .dragging, let touch = dragTouch, touches.contains(touch) else { return }
        updateDrag(touch: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .dragging, let touch = dragTouch, touches.contains(touch) else { return }
        endDrag(commit: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .dragging else { return }
        endDrag(commit: false)
    }

    private func buttonName(at point: CGPoint) -> String? {
        for node in nodes(at: point) {
            var current: SKNode? = node
            while let candidate = current {
                if let name = candidate.name, name.hasPrefix("btn.") {
                    return name
                }
                current = candidate.parent
            }
        }
        return nil
    }

    private func handleButton(_ name: String) {
        switch name {
        case "btn.pause":
            guard state == .idle else { return }
            pauseButton.press()
            AudioManager.shared.play(.uiTap)
            showPauseOverlay()
        case "btn.bomb":
            guard state == .idle || state == .bombTargeting, engine.bombCharges > 0 else { return }
            bombButton.press()
            AudioManager.shared.play(.uiTap)
            Haptics.shared.tap()
            if state == .bombTargeting {
                state = .idle
                bombButton.setActive(false)
                hintLabel.removeAllActions()
                hintLabel.run(.fadeOut(withDuration: 0.2))
            } else {
                state = .bombTargeting
                bombButton.setActive(true)
                showHintLabel("Tap a block to detonate a 3×3 area", duration: 6)
            }
        case "btn.hint":
            guard state == .idle else { return }
            hintButton.press()
            showHint()
        case "btn.reroll":
            guard state == .idle, engine.rerollCharges > 0 else { return }
            rerollButton.press()
            AudioManager.shared.play(.powerup)
            Haptics.shared.tap()
            _ = engine.useReroll()
            trayNode.setPieces(engine.tray, animated: true)
            updatePowerButtons()
            updateUnplayableHints()
            if engine.isGameOver { runGameOver() }
        case "btn.resume":
            hideOverlay()
            state = .idle
        case "btn.retry":
            restart()
        case "btn.menu", "btn.quit":
            goToMenu()
        case "btn.sound":
            Storage.soundOn.toggle()
            AudioManager.shared.play(.uiTap)
            refreshPauseOverlay()
        case "btn.music":
            AudioManager.shared.setMusicEnabled(!Storage.musicOn)
            refreshPauseOverlay()
        case "btn.haptics":
            Storage.hapticsOn.toggle()
            Haptics.shared.tap()
            refreshPauseOverlay()
        default:
            break
        }
    }

    // MARK: - Hint

    /// Asks the evaluator for the strongest placement and shows it on the board.
    private func showHint() {
        guard let suggestion = engine.requestHint() else {
            AudioManager.shared.play(.invalid, volume: 0.5)
            showHintLabel(engine.hintAvailable ? "No move fits — use a power-up"
                                               : "Hint ready in \(engine.turnsUntilHint)")
            return
        }
        AudioManager.shared.play(.powerup, volume: 0.6)
        Haptics.shared.tap()
        boardNode.showHint(cells: suggestion.cells, color: suggestion.color)
        trayNode.pulsePiece(at: suggestion.trayIndex)
        updatePowerButtons()

        let note: String
        if suggestion.clearedCells > 0 {
            note = "Detonates \(suggestion.biggestGroup) blocks for \(suggestion.immediateScore.grouped)"
        } else if suggestion.clusterGain > 0 {
            note = "Grows your biggest cluster by \(suggestion.clusterGain)"
        } else {
            note = "Safest placement — keeps the board open"
        }
        showHintLabel(note, duration: 3.0)
    }

    // MARK: - Dragging

    private func beginDrag(piece: Piece, index: Int, touch: UITouch) {
        state = .dragging
        dragTouch = touch
        dragIndex = index
        trayNode.setPieceHidden(true, at: index)
        trayNode.highlightSlot(index, on: true)

        let node = PieceNode(piece: piece, cellSize: cellSize)
        node.zPosition = 200
        node.setScale(0.7)
        node.run(.scale(to: 1.0, duration: 0.1))
        worldNode.addChild(node)
        dragNode = node

        AudioManager.shared.play(.pickup, volume: 0.7)
        Haptics.shared.tap()
        updateDrag(touch: touch)
    }

    private func updateDrag(touch: UITouch) {
        guard let node = dragNode else { return }
        let point = touch.location(in: worldNode)

        // Centre the piece on the finger and lift it clear of the fingertip.
        let lift = cellSize * 1.35
        node.position = CGPoint(x: point.x + cellSize / 2 - node.pieceWidth / 2,
                                y: point.y + lift + node.pieceHeight - cellSize / 2)

        let inBoard = boardNode.convert(node.position, from: worldNode)
        let col = Int((inBoard.x / cellSize - 0.5).rounded())
        let row = Int((CGFloat(GameConfig.rows) - 0.5 - inBoard.y / cellSize).rounded())

        if let index = dragIndex, engine.canPlace(trayIndex: index, row: row, col: col) {
            let target = GridPoint(row, col)
            if dragTarget != target {
                dragTarget = target
                let cells = node.piece.shape.cells.map { GridPoint($0.row + row, $0.col + col) }
                boardNode.showGhost(cells: cells, color: node.piece.color)
            }
        } else {
            dragTarget = nil
            boardNode.hideGhost()
        }
    }

    private func endDrag(commit: Bool) {
        guard let node = dragNode, let index = dragIndex else { return }
        boardNode.hideGhost()
        trayNode.highlightSlot(index, on: false)

        if commit, let target = dragTarget,
           let result = engine.place(trayIndex: index, row: target.row, col: target.col) {
            node.removeFromParent()
            trayNode.removePiece(at: index)
            dragNode = nil
            dragIndex = nil
            dragTarget = nil
            dragTouch = nil
            play(result: result)
            return
        }

        // Bounce back into the tray.
        let center = trayNode.convert(trayNode.slotCenter(index), to: worldNode)
        let back = SKAction.group([
            .move(to: center, duration: 0.14),
            .scale(to: 0.5, duration: 0.14),
            .fadeOut(withDuration: 0.14),
        ])
        back.timingMode = .easeOut
        node.run(.sequence([back, .removeFromParent()]))
        trayNode.setPieceHidden(false, at: index)
        AudioManager.shared.play(.invalid, volume: 0.5)

        dragNode = nil
        dragIndex = nil
        dragTarget = nil
        dragTouch = nil
        state = .idle
    }

    // MARK: - Bomb

    private func fireBomb(at cell: GridPoint) {
        guard engine.board.contains(cell.row, cell.col) else { return }
        guard let result = engine.useBomb(row: cell.row, col: cell.col) else {
            AudioManager.shared.play(.invalid, volume: 0.6)
            return
        }
        state = .idle
        bombButton.setActive(false)
        hintLabel.removeAllActions()
        hintLabel.run(.fadeOut(withDuration: 0.2))
        AudioManager.shared.play(.bomb)
        Haptics.shared.blast(chainStep: 2, cells: 9)
        shakeCamera(amplitude: 12, duration: 0.35)
        play(result: result, isBomb: true)
    }

    // MARK: - Playing a turn

    private func play(result: TurnResult, isBomb: Bool = false) {
        state = .animating

        if !isBomb {
            // Slam the placed blocks in.
            for cell in result.placedCells {
                guard let color = result.placedColor else { continue }
                let node = boardNode.addBlock(color: color, at: cell)
                node.setScale(1.3)
                node.alpha = 0.4
                node.run(.group([
                    .scale(to: 1.0, duration: 0.11),
                    .fadeAlpha(to: 1.0, duration: 0.08),
                ]))
            }
            AudioManager.shared.play(.place, volume: 0.85)
            Haptics.shared.place()
        }

        var time: TimeInterval = isBomb ? 0.0 : 0.14

        for step in result.steps {
            let stepTime = time
            schedule(stepTime) { [weak self] in
                self?.animateDetonation(step: step)
            }
            schedule(stepTime + 0.20) { [weak self] in
                self?.animateFalls(step: step)
            }
            time += stepDuration
        }

        schedule(time) { [weak self] in
            self?.finishTurn(result: result)
        }
    }

    private func animateDetonation(step: CascadeStep) {
        var centroid = CGPoint.zero
        var count = 0

        for group in step.groups {
            for cell in group.cells {
                let position = boardNode.position(row: cell.row, col: cell.col)
                let inWorld = boardNode.convert(position, to: fxLayer)
                centroid.x += inWorld.x
                centroid.y += inWorld.y
                count += 1

                if let node = boardNode.detachBlock(at: cell) {
                    node.zPosition = 30
                    node.run(.sequence([
                        .group([
                            .scale(to: 1.35, duration: 0.09),
                            .colorize(with: .white, colorBlendFactor: 0.9, duration: 0.06),
                        ]),
                        .group([
                            .scale(to: 0.1, duration: 0.16),
                            .fadeOut(withDuration: 0.16),
                        ]),
                        .removeFromParent(),
                    ]))
                }
                fxLayer.addChild(FX.shatter(at: inWorld, color: group.color, cellSize: cellSize))
            }

            if let first = group.cells.first {
                let position = boardNode.convert(boardNode.position(row: first.row, col: first.col), to: fxLayer)
                fxLayer.addChild(FX.flash(at: position, color: group.color, cellSize: cellSize))
                if step.index > 0 {
                    fxLayer.addChild(FX.shockwave(at: position, color: group.color, radius: cellSize))
                }
            }
        }

        guard count > 0 else { return }
        centroid.x /= CGFloat(count)
        centroid.y /= CGFloat(count)

        let color = step.groups.first.map { Theme.color(for: $0.color) } ?? Theme.accent
        fxLayer.addChild(FX.scorePopup(step.score, at: centroid, color: color,
                                       fontSize: min(34, cellSize * 0.72)))

        let biggest = step.groups.reduce(0) { max($0, $1.cells.count) }
        let threshold = engine.activeThreshold
        let overshoot = max(0, biggest - threshold)

        // Size drives the whole reward signal: the louder, higher and shakier
        // the feedback, the bigger the single-colour blob the player built.
        AudioManager.shared.playBlast(step: step.index, size: overshoot, cells: step.cellCount)
        Haptics.shared.blast(chainStep: step.index + overshoot / 3, cells: step.cellCount)
        shakeCamera(amplitude: min(22, 4 + CGFloat(step.index) * 3 + CGFloat(overshoot) * 1.1))

        if Theme.isBigBlast(size: biggest, threshold: threshold) {
            let title = Theme.blastTitle(size: biggest, threshold: threshold)
            fxLayer.addChild(FX.banner(title: title,
                                       subtitle: "\(biggest) BLOCKS · \(step.score.grouped)",
                                       color: color,
                                       at: CGPoint(x: size.width / 2, y: boardNode.position.y + boardNode.boardSize.height * 0.62),
                                       width: size.width))
            punchCamera(zoom: 1.0 - min(0.06, 0.006 * CGFloat(overshoot)))
        } else if step.index >= 1 {
            let multiplier = String(format: "×%.1f", step.multiplier)
            fxLayer.addChild(FX.banner(title: Theme.chainTitle(depth: step.index + 1),
                                       subtitle: "CHAIN \(multiplier)",
                                       color: color,
                                       at: CGPoint(x: size.width / 2, y: boardNode.position.y + boardNode.boardSize.height * 0.62),
                                       width: size.width))
            punchCamera(zoom: 0.985)
        }

        hudNode.punchScore()
    }

    private func animateFalls(step: CascadeStep) {
        guard !step.falls.isEmpty else { return }
        for move in step.falls {
            let distance = CGFloat(move.to.row - move.from.row)
            boardNode.moveBlock(from: move.from, to: move.to,
                                duration: min(0.26, 0.07 + Double(distance) * 0.026))
        }
        AudioManager.shared.play(.fall, volume: 0.4)
    }

    private func finishTurn(result: TurnResult) {
        hudNode.setScore(engine.score, animated: true)
        hudNode.setHeat(engine.heatFraction, isFever: engine.isFever)
        hudNode.setStreak(engine.streak)
        hudNode.setStage(engine.stage, index: engine.stageIndex)
        updatePowerButtons()
        updateDanger()

        if result.trayRefilled {
            trayNode.setPieces(engine.tray, animated: true)
        }
        updateUnplayableHints()

        if let streakTitle = Theme.streakTitle(result.streak) {
            fxLayer.addChild(FX.banner(title: streakTitle, subtitle: nil, color: Theme.feverB,
                                       at: CGPoint(x: size.width / 2, y: boardNode.position.y + boardNode.boardSize.height * 0.35),
                                       width: size.width))
        }

        for powerUp in result.earnedPowerUps {
            AudioManager.shared.play(.powerup)
            switch powerUp {
            case .bomb: bombButton.pulse()
            case .reroll: rerollButton.pulse()
            }
        }
        if engine.bombCharges == 0 { bombButton.stopPulse() }
        if engine.rerollCharges == 0 { rerollButton.stopPulse() }

        if let stageIndex = result.stageAdvancedTo {
            let stage = GameConfig.stages[stageIndex]
            AudioManager.shared.play(.stageUp)
            fxLayer.addChild(FX.banner(title: "STAGE \(stageIndex + 1)",
                                       subtitle: "\(stage.name) · \(stage.threshold) TO BLAST",
                                       color: Theme.accent,
                                       at: CGPoint(x: size.width / 2, y: boardNode.position.y + boardNode.boardSize.height * 0.5),
                                       width: size.width))
        }

        if result.feverStarted { enterFever() }
        if result.feverEnded { exitFever() }

        if result.isGameOver {
            runGameOver()
            return
        }

        if result.isStuck {
            AudioManager.shared.play(.invalid)
            showHintLabel("No moves left — use a power-up!", duration: 5)
            if engine.bombCharges > 0 { bombButton.pulse() }
            if engine.rerollCharges > 0 { rerollButton.pulse() }
        }

        state = .idle
    }

    private func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        guard delay > 0 else {
            block()
            return
        }
        run(.sequence([.wait(forDuration: delay), .run(block)]))
    }

    // MARK: - Autoplay (CI smoke test only)

    /// Plays the game by itself so the smoke test can screenshot a populated
    /// board. Prefers placements that touch same-colour cells, which is enough
    /// to make it build clusters and set off real cascades.
    private func autoplayStep(remaining: Int) {
        guard remaining > 0, !engine.isGameOver else { return }
        guard state == .idle else {
            schedule(0.2) { [weak self] in self?.autoplayStep(remaining: remaining) }
            return
        }
        guard let move = engine.bestMove(),
              let result = engine.place(trayIndex: move.trayIndex,
                                        row: move.origin.row,
                                        col: move.origin.col) else { return }
        trayNode.removePiece(at: move.trayIndex)
        play(result: result)
        schedule(0.35) { [weak self] in self?.autoplayStep(remaining: remaining - 1) }
    }

    // MARK: - Camera

    private var cameraHome: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Screen shake. The camera is nudged around its resting position, which
    /// keeps the layout anchored — scaling or moving a content node instead
    /// would drift everything toward its origin corner.
    private func shakeCamera(amplitude: CGFloat, duration: TimeInterval = 0.3) {
        let home = cameraHome
        cameraNode.removeAction(forKey: "shake")
        let steps = max(4, Int(duration / 0.035))
        var actions: [SKAction] = []
        for i in 0..<steps {
            let decay = 1.0 - CGFloat(i) / CGFloat(steps)
            let dx = CGFloat.random(in: -amplitude...amplitude) * decay
            let dy = CGFloat.random(in: -amplitude...amplitude) * decay
            actions.append(.move(to: CGPoint(x: home.x + dx, y: home.y + dy),
                                 duration: duration / Double(steps)))
        }
        actions.append(.move(to: home, duration: 0.05))
        cameraNode.run(.sequence(actions), withKey: "shake")
    }

    /// Zoom punch. A camera scale below 1 zooms in.
    private func punchCamera(zoom: CGFloat) {
        cameraNode.removeAction(forKey: "punch")
        cameraNode.run(.sequence([
            .scale(to: zoom, duration: 0.07),
            .scale(to: 1.0, duration: 0.18),
        ]), withKey: "punch")
    }

    // MARK: - Fever

    private func enterFever() {
        AudioManager.shared.play(.feverStart)
        AudioManager.shared.setFever(true)
        Haptics.shared.fever()
        boardNode.setFever(true)
        hudNode.setFeverActive(true)

        feverWash.removeAllActions()
        feverWash.run(.sequence([
            .fadeAlpha(to: 0.34, duration: 0.12),
            .fadeAlpha(to: 0.14, duration: 0.3),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.22, duration: 0.55),
                .fadeAlpha(to: 0.10, duration: 0.55),
            ])),
        ]))

        punchCamera(zoom: 0.94)
        shakeCamera(amplitude: 10, duration: 0.4)
        let palette = engine.feverPalette.map { colorName($0) }.joined(separator: " + ")
        fxLayer.addChild(FX.banner(title: "FEVER!",
                                   subtitle: "×3 SCORE · ONLY \(palette)",
                                   color: Theme.feverB,
                                   at: CGPoint(x: size.width / 2, y: boardNode.position.y + boardNode.boardSize.height * 0.5),
                                   width: size.width))
    }

    private func colorName(_ color: BlockColor) -> String {
        switch color {
        case .cyan: return "CYAN"
        case .magenta: return "MAGENTA"
        case .lime: return "LIME"
        case .amber: return "AMBER"
        case .violet: return "VIOLET"
        case .coral: return "CORAL"
        }
    }

    private func exitFever() {
        AudioManager.shared.play(.feverEnd, volume: 0.7)
        AudioManager.shared.setFever(false)
        boardNode.setFever(false)
        hudNode.setFeverActive(false)
        feverWash.removeAllActions()
        feverWash.run(.fadeAlpha(to: 0, duration: 0.5))
    }

    // MARK: - Overlays

    private func dimPanel(height: CGFloat) -> SKNode {
        let container = SKNode()

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.72), size: size)
        dim.anchorPoint = .zero
        dim.position = .zero
        dim.zPosition = 0
        container.addChild(dim)

        let width = min(size.width - 44, 340)
        let panel = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                cornerRadius: 26)
        panel.fillColor = UIColor(hex: 0x140A2B).withAlphaComponent(0.98)
        panel.strokeColor = Theme.accent.withAlphaComponent(0.5)
        panel.lineWidth = 2
        panel.glowWidth = 2
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 1
        panel.name = "panel"
        container.addChild(panel)

        return container
    }

    private func hideOverlay() {
        overlayLayer.removeAllChildren()
    }

    private func showPauseOverlay() {
        state = .paused
        refreshPauseOverlay()
    }

    private func refreshPauseOverlay() {
        overlayLayer.removeAllChildren()
        let container = dimPanel(height: 380)
        overlayLayer.addChild(container)
        guard let panel = container.childNode(withName: "panel") else { return }

        let title = SKLabelNode(fontNamed: Theme.fontHeavy)
        title.text = "PAUSED"
        title.fontSize = 34
        title.fontColor = Theme.textPrimary
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 142)
        panel.addChild(title)

        let toggles: [(String, String, Bool)] = [
            ("SOUND", "btn.sound", Storage.soundOn),
            ("MUSIC", "btn.music", Storage.musicOn),
            ("HAPTICS", "btn.haptics", Storage.hapticsOn),
        ]
        for (index, toggle) in toggles.enumerated() {
            let button = PillButton(title: "\(toggle.0)   \(toggle.2 ? "ON" : "OFF")",
                                    width: 240, height: 46,
                                    tint: toggle.2 ? Theme.accent : Theme.textSecondary,
                                    fontSize: 17,
                                    identifier: toggle.1)
            button.position = CGPoint(x: 0, y: 74 - CGFloat(index) * 58)
            panel.addChild(button)
        }

        let resume = PillButton(title: "RESUME", width: 240, height: 54, tint: Theme.positive, identifier: "btn.resume")
        resume.position = CGPoint(x: 0, y: -84)
        panel.addChild(resume)

        let quit = PillButton(title: "MAIN MENU", width: 240, height: 46, tint: Theme.feverA, fontSize: 17, identifier: "btn.quit")
        quit.position = CGPoint(x: 0, y: -148)
        panel.addChild(quit)
    }

    // MARK: - Game over

    private func runGameOver() {
        state = .gameOver
        AudioManager.shared.play(.gameOver)
        AudioManager.shared.duckForGameOver()
        AudioManager.shared.setFever(false)
        Haptics.shared.gameOver()
        boardNode.setFever(false)
        feverWash.run(.fadeAlpha(to: 0, duration: 0.4))

        let isRecord = Storage.recordRun(score: engine.score,
                                         bestChain: engine.bestChain,
                                         bestStreak: engine.bestStreak,
                                         blasts: engine.totalBlasts)

        // Drain the board bottom-up so the run visibly ends.
        var delay: TimeInterval = 0.25
        for row in stride(from: GameConfig.rows - 1, through: 0, by: -1) {
            let currentRow = row
            schedule(delay) { [weak self] in
                guard let self = self else { return }
                for col in 0..<GameConfig.cols {
                    let point = GridPoint(currentRow, col)
                    if let node = self.boardNode.detachBlock(at: point) {
                        node.run(.sequence([
                            .group([.fadeOut(withDuration: 0.28), .scale(to: 0.2, duration: 0.28)]),
                            .removeFromParent(),
                        ]))
                    }
                }
            }
            delay += 0.045
        }

        schedule(delay + 0.35) { [weak self] in
            self?.showGameOverPanel(isRecord: isRecord)
        }
    }

    private func showGameOverPanel(isRecord: Bool) {
        if isRecord {
            AudioManager.shared.play(.highScore)
            let confetti = FX.confetti(in: CGRect(origin: .zero, size: size))
            confetti.run(.sequence([.wait(forDuration: 4.0), .removeFromParent()]))
            addChild(confetti)
        }

        let container = dimPanel(height: 420)
        overlayLayer.addChild(container)
        guard let panel = container.childNode(withName: "panel") else { return }

        let title = SKLabelNode(fontNamed: Theme.fontHeavy)
        title.text = isRecord ? "NEW BEST!" : "RUN OVER"
        title.fontSize = 36
        title.fontColor = isRecord ? Theme.feverB : Theme.textPrimary
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 160)
        panel.addChild(title)

        let score = SKLabelNode(fontNamed: Theme.fontHeavy)
        score.text = engine.score.grouped
        score.fontSize = 56
        score.fontColor = Theme.accent
        score.verticalAlignmentMode = .center
        score.position = CGPoint(x: 0, y: 98)
        score.setScale(0.4)
        score.run(.sequence([.scale(to: 1.12, duration: 0.18), .scale(to: 1.0, duration: 0.1)]))
        panel.addChild(score)

        let rows: [(String, String)] = [
            ("BEST", Storage.highScore.grouped),
            ("STAGE REACHED", "\(engine.stageIndex + 1) · \(engine.stage.name)"),
            ("LONGEST CHAIN", "×\(engine.bestChain)"),
            ("BEST STREAK", "\(engine.bestStreak)"),
            ("PLACEMENTS", "\(engine.turn)"),
        ]
        for (index, row) in rows.enumerated() {
            let y = 42 - CGFloat(index) * 28

            let key = SKLabelNode(fontNamed: Theme.fontMedium)
            key.text = row.0
            key.fontSize = 15
            key.fontColor = Theme.textSecondary
            key.horizontalAlignmentMode = .left
            key.verticalAlignmentMode = .center
            key.position = CGPoint(x: -128, y: y)
            panel.addChild(key)

            let value = SKLabelNode(fontNamed: Theme.fontBold)
            value.text = row.1
            value.fontSize = 15
            value.fontColor = Theme.textPrimary
            value.horizontalAlignmentMode = .right
            value.verticalAlignmentMode = .center
            value.position = CGPoint(x: 128, y: y)
            panel.addChild(value)
        }

        let retry = PillButton(title: "PLAY AGAIN", width: 240, height: 56, tint: Theme.positive, identifier: "btn.retry")
        retry.position = CGPoint(x: 0, y: -122)
        retry.pulse()
        panel.addChild(retry)

        let menu = PillButton(title: "MENU", width: 240, height: 46, tint: Theme.accent, fontSize: 17, identifier: "btn.menu")
        menu.position = CGPoint(x: 0, y: -180)
        panel.addChild(menu)
    }

    // MARK: - Navigation

    private func restart() {
        AudioManager.shared.play(.uiTap)
        hideOverlay()
        removeAllActions()
        fxLayer.removeAllChildren()
        engine.startNewGame()
        exitFever()
        AudioManager.shared.startMusic()
        refreshAll(animated: true)
        state = .idle
    }

    private func goToMenu() {
        AudioManager.shared.play(.uiTap)
        let menu = MenuScene(size: size)
        menu.scaleMode = .resizeFill
        view?.presentScene(menu, transition: SKTransition.fade(withDuration: 0.35))
    }
}
