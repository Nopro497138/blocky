import SpriteKit
import UIKit

final class MenuScene: SKScene {

    private let overlayLayer = SKNode()
    private var titleNode: SKNode!

    override func didMove(to view: SKView) {
        backgroundColor = Theme.backgroundTop
        scaleMode = .resizeFill
        anchorPoint = .zero

        AudioManager.shared.configure()
        AudioManager.shared.startMusic()
        AudioManager.shared.setFever(false)

        overlayLayer.zPosition = 500
        addChild(overlayLayer)

        buildBackground()
        buildContent(safeTop: view.safeAreaInsets.top, safeBottom: view.safeAreaInsets.bottom)
    }

    // MARK: - Build

    private func buildBackground() {
        let background = SKSpriteNode(texture: BlockTextureFactory.shared.verticalGradient(
            size: CGSize(width: 64, height: 128),
            top: Theme.backgroundBottom,
            bottom: Theme.backgroundTop))
        background.anchorPoint = .zero
        background.size = size
        background.zPosition = -100
        addChild(background)

        for (index, color) in BlockColor.allCases.enumerated() {
            let glow = SKSpriteNode(texture: BlockTextureFactory.shared.radialGlow(diameter: 256, color: Theme.color(for: color)))
            glow.size = CGSize(width: size.width, height: size.width)
            glow.alpha = 0.09
            glow.blendMode = .add
            glow.zPosition = -99
            glow.position = CGPoint(x: size.width * (index % 2 == 0 ? 0.18 : 0.82),
                                    y: size.height * (0.12 + 0.16 * CGFloat(index)))
            glow.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.16, duration: 2.0 + Double(index) * 0.3),
                .fadeAlpha(to: 0.05, duration: 2.0 + Double(index) * 0.3),
            ])))
            addChild(glow)
        }

        // Falling demo blocks, purely decorative.
        run(.repeatForever(.sequence([
            .run { [weak self] in self?.spawnDecorBlock() },
            .wait(forDuration: 0.55),
        ])), withKey: "decor")
    }

    private func spawnDecorBlock() {
        let cell: CGFloat = 26
        guard let color = BlockColor.allCases.randomElement() else { return }
        let node = SKSpriteNode(texture: BlockTextureFactory.shared.texture(for: color, size: cell))
        node.size = CGSize(width: cell, height: cell)
        node.alpha = 0.30
        node.zPosition = -90
        node.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + cell)
        node.zRotation = CGFloat.random(in: -0.3...0.3)
        addChild(node)
        let duration = Double.random(in: 5.5...9.0)
        node.run(.sequence([
            .group([
                .moveBy(x: CGFloat.random(in: -40...40), y: -(size.height + cell * 2), duration: duration),
                .rotate(byAngle: CGFloat.random(in: -1.2...1.2), duration: duration),
            ]),
            .removeFromParent(),
        ]))
    }

    private func buildContent(safeTop: CGFloat, safeBottom: CGFloat) {
        let centerX = size.width / 2

        titleNode = SKNode()
        titleNode.position = CGPoint(x: centerX, y: size.height - safeTop - 150)
        addChild(titleNode)

        let title = SKLabelNode(fontNamed: Theme.fontHeavy)
        title.text = "CHROMA"
        title.fontSize = min(64, size.width * 0.17)
        title.fontColor = Theme.textPrimary
        title.verticalAlignmentMode = .center
        titleNode.addChild(title)

        let subtitle = SKLabelNode(fontNamed: Theme.fontHeavy)
        subtitle.text = "CASCADE"
        subtitle.fontSize = min(64, size.width * 0.17)
        subtitle.fontColor = Theme.accent
        subtitle.verticalAlignmentMode = .center
        subtitle.position = CGPoint(x: 0, y: -title.fontSize * 0.92)
        titleNode.addChild(subtitle)

        let tagline = SKLabelNode(fontNamed: Theme.fontBold)
        tagline.text = "CONNECT · DETONATE · CHAIN"
        tagline.fontSize = min(15, size.width * 0.04)
        tagline.fontColor = Theme.textSecondary
        tagline.verticalAlignmentMode = .center
        tagline.position = CGPoint(x: 0, y: -title.fontSize * 1.7)
        titleNode.addChild(tagline)

        titleNode.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 7, duration: 1.6),
            .moveBy(x: 0, y: -7, duration: 1.6),
        ])))

        // Sample row of blocks under the title, showing the palette.
        let sampleCell = min(34, size.width * 0.085)
        let sample = SKNode()
        sample.position = CGPoint(x: centerX, y: titleNode.position.y - 140)
        addChild(sample)
        let colors = BlockColor.allCases
        for (index, color) in colors.enumerated() {
            let node = SKSpriteNode(texture: BlockTextureFactory.shared.texture(for: color, size: sampleCell))
            node.size = CGSize(width: sampleCell, height: sampleCell)
            node.position = CGPoint(x: (CGFloat(index) - CGFloat(colors.count - 1) / 2) * (sampleCell + 6), y: 0)
            sample.addChild(node)
            node.run(.repeatForever(.sequence([
                .wait(forDuration: Double(index) * 0.12),
                .scale(to: 1.14, duration: 0.28),
                .scale(to: 1.0, duration: 0.28),
                .wait(forDuration: 1.6 - Double(index) * 0.12),
            ])))
        }

        let best = SKLabelNode(fontNamed: Theme.fontBold)
        best.text = "BEST  \(Storage.highScore.grouped)"
        best.fontSize = min(20, size.width * 0.052)
        best.fontColor = Theme.feverB
        best.verticalAlignmentMode = .center
        best.position = CGPoint(x: centerX, y: sample.position.y - 62)
        addChild(best)

        if Storage.gamesPlayed > 0 {
            let stats = SKLabelNode(fontNamed: Theme.fontMedium)
            stats.text = "\(Storage.gamesPlayed) runs · best chain ×\(Storage.bestChain) · \(Storage.totalBlasts.grouped) blasts"
            stats.fontSize = min(13, size.width * 0.034)
            stats.fontColor = Theme.textSecondary
            stats.verticalAlignmentMode = .center
            stats.position = CGPoint(x: centerX, y: best.position.y - 26)
            addChild(stats)
        }

        let buttonWidth = min(260, size.width - 72)
        let playY = max(safeBottom + 190, size.height * 0.26)

        let play = PillButton(title: "PLAY", width: buttonWidth, height: 62,
                              tint: Theme.positive, fontSize: 26, identifier: "btn.play")
        play.position = CGPoint(x: centerX, y: playY)
        play.pulse()
        addChild(play)

        let how = PillButton(title: "HOW TO PLAY", width: buttonWidth, height: 46,
                             tint: Theme.accent, fontSize: 17, identifier: "btn.how")
        how.position = CGPoint(x: centerX, y: playY - 74)
        addChild(how)

        let settings = PillButton(title: "SETTINGS", width: buttonWidth, height: 46,
                                  tint: Theme.textSecondary, fontSize: 17, identifier: "btn.settings")
        settings.position = CGPoint(x: centerX, y: playY - 132)
        addChild(settings)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)

        guard let name = buttonName(at: point) else {
            if !overlayLayer.children.isEmpty { closeOverlay() }
            return
        }

        AudioManager.shared.play(.uiTap)
        Haptics.shared.tap()

        switch name {
        case "btn.play":
            startGame()
        case "btn.how":
            showHowToPlay()
        case "btn.settings":
            showSettings()
        case "btn.close":
            closeOverlay()
        case "btn.sound":
            Storage.soundOn.toggle()
            showSettings()
        case "btn.music":
            AudioManager.shared.setMusicEnabled(!Storage.musicOn)
            showSettings()
        case "btn.haptics":
            Storage.hapticsOn.toggle()
            showSettings()
        case "btn.reset":
            Storage.highScore = 0
            Storage.bestChain = 0
            Storage.bestStreak = 0
            Storage.gamesPlayed = 0
            Storage.totalBlasts = 0
            closeOverlay()
            let fresh = MenuScene(size: size)
            fresh.scaleMode = .resizeFill
            view?.presentScene(fresh, transition: SKTransition.fade(withDuration: 0.2))
        default:
            break
        }
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

    private func startGame() {
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: SKTransition.fade(withDuration: 0.35))
    }

    // MARK: - Overlays

    private func closeOverlay() {
        overlayLayer.removeAllChildren()
    }

    private func panel(height: CGFloat) -> SKShapeNode {
        overlayLayer.removeAllChildren()

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.75), size: size)
        dim.anchorPoint = .zero
        dim.zPosition = 0
        overlayLayer.addChild(dim)

        let width = min(size.width - 40, 350)
        let node = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                               cornerRadius: 26)
        node.fillColor = UIColor(hex: 0x140A2B).withAlphaComponent(0.98)
        node.strokeColor = Theme.accent.withAlphaComponent(0.5)
        node.lineWidth = 2
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.zPosition = 1
        overlayLayer.addChild(node)
        return node
    }

    private func showHowToPlay() {
        let card = panel(height: 430)

        let title = SKLabelNode(fontNamed: Theme.fontHeavy)
        title.text = "HOW TO PLAY"
        title.fontSize = 26
        title.fontColor = Theme.textPrimary
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 178)
        card.addChild(title)

        let lines: [(String, UIColor)] = [
            ("Drag block shapes onto the grid.", Theme.textPrimary),
            ("They lock exactly where you drop them.", Theme.textSecondary),
            ("", Theme.textSecondary),
            ("Connect 5+ blocks of ONE colour", Theme.accent),
            ("and the whole group detonates.", Theme.textSecondary),
            ("", Theme.textSecondary),
            ("Blocks above a blast FALL DOWN.", Theme.feverB),
            ("If that forms 3+ of a colour, it blasts", Theme.textSecondary),
            ("again — that is a CHAIN. ×1.4, ×2, ×3…", Theme.textSecondary),
            ("", Theme.textSecondary),
            ("Chains fill the HEAT bar. Fill it and", Theme.feverA),
            ("FEVER doubles score and makes", Theme.textSecondary),
            ("blasting easier for 8 moves.", Theme.textSecondary),
            ("", Theme.textSecondary),
            ("Every 15–50 moves the stage rises:", Theme.textPrimary),
            ("more colours, bigger groups needed.", Theme.textSecondary),
            ("Game over when nothing fits.", Theme.textSecondary),
        ]
        for (index, line) in lines.enumerated() {
            guard !line.0.isEmpty else { continue }
            let label = SKLabelNode(fontNamed: Theme.fontMedium)
            label.text = line.0
            label.fontSize = 14
            label.fontColor = line.1
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: 140 - CGFloat(index) * 18)
            card.addChild(label)
        }

        let close = PillButton(title: "GOT IT", width: 200, height: 46, tint: Theme.positive,
                               fontSize: 18, identifier: "btn.close")
        close.position = CGPoint(x: 0, y: -172)
        card.addChild(close)
    }

    private func showSettings() {
        let card = panel(height: 340)

        let title = SKLabelNode(fontNamed: Theme.fontHeavy)
        title.text = "SETTINGS"
        title.fontSize = 26
        title.fontColor = Theme.textPrimary
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 128)
        card.addChild(title)

        let toggles: [(String, String, Bool)] = [
            ("SOUND", "btn.sound", Storage.soundOn),
            ("MUSIC", "btn.music", Storage.musicOn),
            ("HAPTICS", "btn.haptics", Storage.hapticsOn),
        ]
        for (index, toggle) in toggles.enumerated() {
            let button = PillButton(title: "\(toggle.0)   \(toggle.2 ? "ON" : "OFF")",
                                    width: 240, height: 46,
                                    tint: toggle.2 ? Theme.accent : Theme.textSecondary,
                                    fontSize: 17, identifier: toggle.1)
            button.position = CGPoint(x: 0, y: 62 - CGFloat(index) * 56)
            card.addChild(button)
        }

        let reset = PillButton(title: "RESET STATS", width: 240, height: 42, tint: Theme.dangerColor,
                               fontSize: 15, identifier: "btn.reset")
        reset.position = CGPoint(x: 0, y: -104)
        card.addChild(reset)

        let close = PillButton(title: "CLOSE", width: 240, height: 46, tint: Theme.positive,
                               fontSize: 17, identifier: "btn.close")
        close.position = CGPoint(x: 0, y: -154)
        card.addChild(close)
    }
}
