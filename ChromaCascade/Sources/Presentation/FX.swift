import SpriteKit
import UIKit

/// Every piece of visual "juice" lives here so the scene stays about game flow.
enum FX {

    // MARK: - Particles

    /// The shatter burst a detonated cell leaves behind.
    static func shatter(at position: CGPoint, color: BlockColor, cellSize: CGFloat, intensity: CGFloat = 1.0) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = BlockTextureFactory.shared.shardTexture()
        emitter.particleBirthRate = 3000
        emitter.numParticlesToEmit = Int(10 * intensity)
        emitter.particleLifetime = 0.55
        emitter.particleLifetimeRange = 0.3
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = 150 * intensity
        emitter.particleSpeedRange = 110
        emitter.yAcceleration = -420
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.9
        emitter.particleScale = cellSize / 40
        emitter.particleScaleRange = cellSize / 90
        emitter.particleScaleSpeed = -0.45
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 6
        emitter.particleColor = Theme.color(for: color)
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        emitter.position = position
        emitter.zPosition = 60
        emitter.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
        return emitter
    }

    /// Bright core flash at the centre of a detonation.
    static func flash(at position: CGPoint, color: BlockColor, cellSize: CGFloat, scale: CGFloat = 1.0) -> SKSpriteNode {
        let diameter = cellSize * 3.2 * scale
        let node = SKSpriteNode(texture: BlockTextureFactory.shared.radialGlow(diameter: 128, color: Theme.glowColor(for: color)))
        node.size = CGSize(width: diameter, height: diameter)
        node.position = position
        node.blendMode = .add
        node.zPosition = 55
        node.alpha = 0.0
        node.setScale(0.35)
        node.run(.sequence([
            .group([.fadeAlpha(to: 0.95, duration: 0.06), .scale(to: 1.0, duration: 0.09)]),
            .group([.fadeOut(withDuration: 0.32), .scale(to: 1.45, duration: 0.32)]),
            .removeFromParent(),
        ]))
        return node
    }

    /// Expanding ring — reads as the shockwave that triggers the next chain rung.
    static func shockwave(at position: CGPoint, color: BlockColor, radius: CGFloat) -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: radius * 0.3)
        ring.strokeColor = Theme.glowColor(for: color)
        ring.lineWidth = 4
        ring.fillColor = .clear
        ring.glowWidth = 6
        ring.position = position
        ring.zPosition = 54
        ring.blendMode = .add
        ring.run(.sequence([
            .group([.scale(to: 3.2, duration: 0.42), .fadeOut(withDuration: 0.42)]),
            .removeFromParent(),
        ]))
        return ring
    }

    // MARK: - Text

    static func scorePopup(_ amount: Int, at position: CGPoint, color: UIColor, fontSize: CGFloat) -> SKNode {
        let label = SKLabelNode(fontNamed: Theme.fontHeavy)
        label.text = "+\(amount.grouped)"
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = position
        label.zPosition = 90
        label.setScale(0.4)

        let shadow = SKLabelNode(fontNamed: Theme.fontHeavy)
        shadow.text = label.text
        shadow.fontSize = fontSize
        shadow.fontColor = UIColor.black.withAlphaComponent(0.55)
        shadow.horizontalAlignmentMode = .center
        shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: 1.5, y: -2)
        shadow.zPosition = -1
        label.addChild(shadow)

        label.run(.sequence([
            .group([.scale(to: 1.15, duration: 0.12), .moveBy(x: 0, y: 14, duration: 0.12)]),
            .scale(to: 1.0, duration: 0.06),
            .wait(forDuration: 0.22),
            .group([.moveBy(x: 0, y: 46, duration: 0.42), .fadeOut(withDuration: 0.42)]),
            .removeFromParent(),
        ]))
        return label
    }

    /// The big centred banner: "TRIPLE ×2.0", "FEVER!", "STAGE 4".
    static func banner(title: String, subtitle: String?, color: UIColor, at position: CGPoint, width: CGFloat) -> SKNode {
        let container = SKNode()
        container.position = position
        container.zPosition = 120

        let titleLabel = SKLabelNode(fontNamed: Theme.fontHeavy)
        titleLabel.text = title
        titleLabel.fontSize = min(54, width * 0.14)
        titleLabel.fontColor = color
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        container.addChild(titleLabel)

        if let subtitle = subtitle {
            let sub = SKLabelNode(fontNamed: Theme.fontBold)
            sub.text = subtitle
            sub.fontSize = min(26, width * 0.068)
            sub.fontColor = Theme.textPrimary
            sub.horizontalAlignmentMode = .center
            sub.verticalAlignmentMode = .center
            sub.position = CGPoint(x: 0, y: -titleLabel.fontSize * 0.78)
            container.addChild(sub)
        }

        container.setScale(0.2)
        container.alpha = 0
        container.run(.sequence([
            .group([.scale(to: 1.12, duration: 0.13), .fadeIn(withDuration: 0.1)]),
            .scale(to: 1.0, duration: 0.08),
            .wait(forDuration: 0.5),
            .group([.scale(to: 1.35, duration: 0.28), .fadeOut(withDuration: 0.28)]),
            .removeFromParent(),
        ]))
        return container
    }

    // MARK: - Camera

    /// Screen shake by nudging a container node. Amplitude scales with the hit.
    static func shake(_ node: SKNode, amplitude: CGFloat, duration: TimeInterval = 0.3) {
        node.removeAction(forKey: "shake")
        let steps = max(4, Int(duration / 0.035))
        var actions: [SKAction] = []
        for i in 0..<steps {
            let decay = 1.0 - CGFloat(i) / CGFloat(steps)
            let dx = CGFloat.random(in: -amplitude...amplitude) * decay
            let dy = CGFloat.random(in: -amplitude...amplitude) * decay
            actions.append(.move(to: CGPoint(x: dx, y: dy), duration: duration / Double(steps)))
        }
        actions.append(.move(to: .zero, duration: 0.05))
        node.run(.sequence(actions), withKey: "shake")
    }

    /// Quick zoom punch for the biggest moments.
    static func punch(_ node: SKNode, scale: CGFloat = 1.04) {
        node.removeAction(forKey: "punch")
        node.run(.sequence([
            .scale(to: scale, duration: 0.07),
            .scale(to: 1.0, duration: 0.16),
        ]), withKey: "punch")
    }

    // MARK: - Confetti

    static func confetti(in rect: CGRect) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = BlockTextureFactory.shared.shardTexture()
        emitter.particleBirthRate = 160
        emitter.numParticlesToEmit = 260
        emitter.particleLifetime = 3.2
        emitter.particlePositionRange = CGVector(dx: rect.width, dy: 0)
        emitter.position = CGPoint(x: rect.midX, y: rect.maxY)
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 5
        emitter.particleSpeed = 190
        emitter.particleSpeedRange = 110
        emitter.yAcceleration = -180
        emitter.particleAlphaSpeed = -0.28
        emitter.particleScale = 0.9
        emitter.particleScaleRange = 0.5
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 5
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = confettiColors()
        emitter.zPosition = 200
        return emitter
    }

    private static func confettiColors() -> SKKeyframeSequence {
        let colors = BlockColor.allCases.map { Theme.color(for: $0) }
        let times: [NSNumber] = colors.enumerated().map { NSNumber(value: Double($0.offset) / Double(max(1, colors.count - 1))) }
        return SKKeyframeSequence(keyframeValues: colors, times: times)
    }
}
