import SpriteKit

/// A rounded, glowing, tappable button. `name` doubles as the action identifier.
final class PillButton: SKNode {

    let width: CGFloat
    let height: CGFloat
    private let background: SKShapeNode
    private let label: SKLabelNode
    private let badge: SKLabelNode
    private var tint: UIColor

    init(title: String, width: CGFloat, height: CGFloat, tint: UIColor, fontSize: CGFloat? = nil, identifier: String) {
        self.width = width
        self.height = height
        self.tint = tint
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        background = SKShapeNode(rect: rect, cornerRadius: height / 2)
        label = SKLabelNode(fontNamed: Theme.fontHeavy)
        badge = SKLabelNode(fontNamed: Theme.fontBold)
        super.init()

        background.fillColor = tint.withAlphaComponent(0.16)
        background.strokeColor = tint.withAlphaComponent(0.9)
        background.lineWidth = 2
        background.glowWidth = 2
        addChild(background)

        label.text = title
        label.fontSize = fontSize ?? height * 0.42
        label.fontColor = Theme.textPrimary
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        addChild(label)

        badge.fontSize = height * 0.34
        badge.fontColor = Theme.textPrimary
        badge.horizontalAlignmentMode = .center
        badge.verticalAlignmentMode = .center
        badge.position = CGPoint(x: width / 2 - 8, y: height / 2 - 6)
        badge.isHidden = true
        addChild(badge)

        self.name = identifier
        isUserInteractionEnabled = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        label.text = title
    }

    func setBadge(_ value: Int?) {
        if let value = value, value > 0 {
            badge.text = "\(value)"
            badge.isHidden = false
        } else {
            badge.isHidden = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        alpha = enabled ? 1.0 : 0.32
    }

    func setActive(_ active: Bool) {
        background.fillColor = tint.withAlphaComponent(active ? 0.55 : 0.16)
    }

    func press() {
        removeAction(forKey: "press")
        run(.sequence([.scale(to: 0.92, duration: 0.06), .scale(to: 1.0, duration: 0.1)]), withKey: "press")
    }

    func pulse() {
        removeAction(forKey: "pulse")
        run(.repeatForever(.sequence([
            .scale(to: 1.06, duration: 0.45),
            .scale(to: 1.0, duration: 0.45),
        ])), withKey: "pulse")
    }

    func stopPulse() {
        removeAction(forKey: "pulse")
        setScale(1.0)
    }
}

/// Score, best, stage and the heat meter that fills toward Fever.
final class HUDNode: SKNode {

    private let width: CGFloat
    private let scoreLabel = SKLabelNode(fontNamed: Theme.fontHeavy)
    private let bestLabel = SKLabelNode(fontNamed: Theme.fontMedium)
    private let stageLabel = SKLabelNode(fontNamed: Theme.fontBold)
    private let streakLabel = SKLabelNode(fontNamed: Theme.fontBold)
    private let heatTrack: SKShapeNode
    private let heatFill: SKSpriteNode
    private let heatLabel = SKLabelNode(fontNamed: Theme.fontBold)
    private let heatWidth: CGFloat
    private var displayedScore = 0

    init(width: CGFloat) {
        // Everything here must come from locals: reading a stored property of
        // self before super.init() is not allowed.
        let trackWidth = width * 0.62
        self.width = width
        self.heatWidth = trackWidth
        let trackRect = CGRect(x: -trackWidth / 2, y: -5, width: trackWidth, height: 10)
        heatTrack = SKShapeNode(rect: trackRect, cornerRadius: 5)
        heatFill = SKSpriteNode(color: Theme.accent, size: CGSize(width: 1, height: 8))
        super.init()

        scoreLabel.fontSize = min(52, width * 0.135)
        scoreLabel.fontColor = Theme.textPrimary
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.text = "0"
        addChild(scoreLabel)

        bestLabel.fontSize = min(15, width * 0.04)
        bestLabel.fontColor = Theme.textSecondary
        bestLabel.horizontalAlignmentMode = .left
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: -width / 2, y: scoreLabel.fontSize * 0.72)
        addChild(bestLabel)

        stageLabel.fontSize = min(15, width * 0.04)
        stageLabel.fontColor = Theme.accent
        stageLabel.horizontalAlignmentMode = .right
        stageLabel.verticalAlignmentMode = .center
        stageLabel.position = CGPoint(x: width / 2, y: scoreLabel.fontSize * 0.72)
        addChild(stageLabel)

        streakLabel.fontSize = min(16, width * 0.042)
        streakLabel.fontColor = Theme.feverB
        streakLabel.horizontalAlignmentMode = .center
        streakLabel.verticalAlignmentMode = .center
        streakLabel.position = CGPoint(x: 0, y: -scoreLabel.fontSize * 0.62)
        streakLabel.alpha = 0
        addChild(streakLabel)

        heatTrack.fillColor = UIColor(white: 1.0, alpha: 0.07)
        heatTrack.strokeColor = UIColor(white: 1.0, alpha: 0.10)
        heatTrack.lineWidth = 1
        heatTrack.position = CGPoint(x: 0, y: -scoreLabel.fontSize * 1.05)
        addChild(heatTrack)

        heatFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        heatFill.position = CGPoint(x: -heatWidth / 2 + 1, y: 0)
        heatFill.zPosition = 1
        heatTrack.addChild(heatFill)

        heatLabel.fontSize = min(12, width * 0.032)
        heatLabel.fontColor = Theme.textSecondary
        heatLabel.horizontalAlignmentMode = .center
        heatLabel.verticalAlignmentMode = .center
        heatLabel.position = CGPoint(x: 0, y: -16)
        heatLabel.text = "HEAT"
        heatTrack.addChild(heatLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var bottomY: CGFloat {
        heatTrack.position.y - 26
    }

    // MARK: - Updates

    func setBest(_ value: Int) {
        bestLabel.text = "BEST  \(value.grouped)"
    }

    func setStage(_ stage: Stage, index: Int) {
        stageLabel.text = "\(index + 1) · \(stage.name)"
    }

    /// Counts the score up instead of snapping — a rolling number reads as reward.
    func setScore(_ value: Int, animated: Bool) {
        guard animated, value != displayedScore else {
            displayedScore = value
            scoreLabel.text = value.grouped
            return
        }
        let from = displayedScore
        let delta = value - from
        displayedScore = value
        removeAction(forKey: "count")
        let duration = min(0.6, 0.18 + Double(abs(delta)) / 40000.0)
        let steps = max(1, Int(duration / 0.03))
        var actions: [SKAction] = []
        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let eased = 1 - pow(1 - progress, 3)
            let shown = from + Int(Double(delta) * eased)
            actions.append(.run { [weak self] in self?.scoreLabel.text = shown.grouped })
            actions.append(.wait(forDuration: duration / Double(steps)))
        }
        actions.append(.run { [weak self] in self?.scoreLabel.text = value.grouped })
        run(.sequence(actions), withKey: "count")
        punchScore()
    }

    func punchScore() {
        scoreLabel.removeAction(forKey: "punch")
        scoreLabel.run(.sequence([
            .scale(to: 1.14, duration: 0.07),
            .scale(to: 1.0, duration: 0.14),
        ]), withKey: "punch")
    }

    func setHeat(_ fraction: Double, isFever: Bool) {
        let clamped = CGFloat(max(0, min(1, fraction)))
        let target = max(1, (heatWidth - 2) * clamped)
        heatFill.removeAction(forKey: "heat")
        heatFill.run(.resize(toWidth: target, duration: 0.22), withKey: "heat")
        if isFever {
            heatFill.color = Theme.feverA
            heatLabel.text = "FEVER"
            heatLabel.fontColor = Theme.feverB
        } else {
            heatFill.color = clamped > 0.7 ? Theme.feverB : Theme.accent
            heatLabel.text = "HEAT"
            heatLabel.fontColor = Theme.textSecondary
        }
    }

    /// Shows the fever meter as fully lit for the duration of fever.
    func setFeverActive(_ active: Bool) {
        if active {
            heatFill.removeAction(forKey: "heat")
            heatFill.size = CGSize(width: heatWidth - 2, height: 8)
            heatTrack.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.3),
                .fadeAlpha(to: 1.0, duration: 0.3),
            ])), withKey: "feverPulse")
        } else {
            heatTrack.removeAction(forKey: "feverPulse")
            heatTrack.alpha = 1
        }
    }

    func setStreak(_ streak: Int) {
        if streak >= 2 {
            streakLabel.text = "STREAK ×\(streak)"
            streakLabel.removeAction(forKey: "streak")
            streakLabel.run(.sequence([
                .fadeAlpha(to: 1.0, duration: 0.1),
                .scale(to: 1.15, duration: 0.08),
                .scale(to: 1.0, duration: 0.1),
            ]), withKey: "streak")
        } else {
            streakLabel.run(.fadeAlpha(to: 0, duration: 0.2))
        }
    }
}
