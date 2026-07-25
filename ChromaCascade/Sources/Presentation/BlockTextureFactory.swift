import SpriteKit
import UIKit

/// Blocks are drawn once per colour and size into a texture, then reused. Eighty
/// SKShapeNodes would cost a draw call each; eighty sprites sharing six textures
/// batch into almost nothing.
final class BlockTextureFactory {

    static let shared = BlockTextureFactory()

    private var cache: [String: SKTexture] = [:]

    private init() {}

    func reset() {
        cache.removeAll()
    }

    // MARK: - Blocks

    func texture(for color: BlockColor, size: CGFloat) -> SKTexture {
        let key = "block-\(color.rawValue)-\(Int(size.rounded()))"
        if let cached = cache[key] { return cached }

        let base = Theme.color(for: color)
        let face = Theme.faceColor(for: color)
        let image = render(size: size) { context, rect in
            let inset = rect.insetBy(dx: size * 0.045, dy: size * 0.045)
            let radius = size * 0.22
            let path = UIBezierPath(roundedRect: inset, cornerRadius: radius)

            // outer glow
            context.saveGState()
            context.setShadow(offset: .zero, blur: size * 0.28, color: base.withAlphaComponent(0.85).cgColor)
            face.setFill()
            path.fill()
            context.restoreGState()

            // body gradient
            context.saveGState()
            path.addClip()
            let colors = [base.mixed(with: .white, amount: 0.30).cgColor,
                          face.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0.0, 1.0]) {
                context.drawLinearGradient(gradient,
                                           start: CGPoint(x: inset.minX, y: inset.minY),
                                           end: CGPoint(x: inset.maxX, y: inset.maxY),
                                           options: [])
            }
            context.restoreGState()

            // rim
            base.mixed(with: .white, amount: 0.55).withAlphaComponent(0.95).setStroke()
            path.lineWidth = max(1.0, size * 0.055)
            path.stroke()

            // top highlight
            let highlight = UIBezierPath(roundedRect: CGRect(x: inset.minX + size * 0.14,
                                                             y: inset.minY + size * 0.11,
                                                             width: inset.width - size * 0.28,
                                                             height: size * 0.16),
                                         cornerRadius: size * 0.08)
            UIColor.white.withAlphaComponent(0.32).setFill()
            highlight.fill()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// The translucent preview of where a dragged piece will land.
    func ghostTexture(size: CGFloat, color: BlockColor) -> SKTexture {
        let key = "ghost-\(color.rawValue)-\(Int(size.rounded()))"
        if let cached = cache[key] { return cached }

        let base = Theme.color(for: color)
        let image = render(size: size) { _, rect in
            let inset = rect.insetBy(dx: size * 0.08, dy: size * 0.08)
            let path = UIBezierPath(roundedRect: inset, cornerRadius: size * 0.2)
            base.withAlphaComponent(0.22).setFill()
            path.fill()
            base.withAlphaComponent(0.9).setStroke()
            path.lineWidth = max(1.0, size * 0.07)
            path.stroke()
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// Empty grid slot.
    func slotTexture(size: CGFloat) -> SKTexture {
        let key = "slot-\(Int(size.rounded()))"
        if let cached = cache[key] { return cached }
        let image = render(size: size) { _, rect in
            let inset = rect.insetBy(dx: size * 0.07, dy: size * 0.07)
            let path = UIBezierPath(roundedRect: inset, cornerRadius: size * 0.2)
            UIColor(white: 1.0, alpha: 0.045).setFill()
            path.fill()
            UIColor(white: 1.0, alpha: 0.05).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    // MARK: - Particles

    /// Soft additive dot used by every emitter in the game.
    func sparkTexture() -> SKTexture {
        let key = "spark"
        if let cached = cache[key] { return cached }
        let dimension: CGFloat = 32
        let image = render(size: dimension) { context, rect in
            let colors = [UIColor.white.withAlphaComponent(1.0).cgColor,
                          UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0.0, 1.0]) {
                context.drawRadialGradient(gradient,
                                           startCenter: CGPoint(x: rect.midX, y: rect.midY),
                                           startRadius: 0,
                                           endCenter: CGPoint(x: rect.midX, y: rect.midY),
                                           endRadius: rect.width / 2,
                                           options: [])
            }
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// Square shard for the shatter effect.
    func shardTexture() -> SKTexture {
        let key = "shard"
        if let cached = cache[key] { return cached }
        let dimension: CGFloat = 16
        let image = render(size: dimension) { _, rect in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 3).fill()
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    // MARK: - Backgrounds

    func verticalGradient(size: CGSize, top: UIColor, bottom: UIColor) -> SKTexture {
        let key = "grad-\(Int(size.width))x\(Int(size.height))-\(top.hashValue)-\(bottom.hashValue)"
        if let cached = cache[key] { return cached }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0.0, 1.0]) {
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
            }
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// Soft radial glow used for the fever wash and the danger vignette.
    func radialGlow(diameter: CGFloat, color: UIColor) -> SKTexture {
        let key = "glow-\(Int(diameter))-\(color.hashValue)"
        if let cached = cache[key] { return cached }
        let image = render(size: diameter) { context, rect in
            let colors = [color.withAlphaComponent(0.9).cgColor,
                          color.withAlphaComponent(0.0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0.0, 1.0]) {
                context.drawRadialGradient(gradient,
                                           startCenter: CGPoint(x: rect.midX, y: rect.midY),
                                           startRadius: 0,
                                           endCenter: CGPoint(x: rect.midX, y: rect.midY),
                                           endRadius: rect.width / 2,
                                           options: [])
            }
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    // MARK: - Helper

    private func render(size: CGFloat, _ draw: (CGContext, CGRect) -> Void) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        return renderer.image { ctx in
            draw(ctx.cgContext, rect)
        }
    }
}
