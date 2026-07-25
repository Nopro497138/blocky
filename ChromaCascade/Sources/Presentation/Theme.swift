import SpriteKit
import UIKit

/// Neon / synthwave look. Every colour the game draws comes from here.
enum Theme {

    // MARK: - Palette

    static func color(for block: BlockColor) -> UIColor {
        switch block {
        case .cyan:    return UIColor(hex: 0x00E5FF)
        case .magenta: return UIColor(hex: 0xFF2D95)
        case .lime:    return UIColor(hex: 0x9BFF3C)
        case .amber:   return UIColor(hex: 0xFFB020)
        case .violet:  return UIColor(hex: 0xA64BFF)
        case .coral:   return UIColor(hex: 0xFF5A47)
        }
    }

    /// A darker version used for the block's inner face, so blocks read as lit
    /// panels rather than flat squares.
    static func faceColor(for block: BlockColor) -> UIColor {
        color(for: block).mixed(with: .black, amount: 0.42)
    }

    static func glowColor(for block: BlockColor) -> UIColor {
        color(for: block).mixed(with: .white, amount: 0.35)
    }

    static let backgroundTop = UIColor(hex: 0x0B0418)
    static let backgroundBottom = UIColor(hex: 0x1A0733)
    static let boardFill = UIColor(white: 1.0, alpha: 0.035)
    static let boardStroke = UIColor(hex: 0x8A5CFF).withAlphaComponent(0.35)
    static let gridLine = UIColor(white: 1.0, alpha: 0.06)
    static let ghostFill = UIColor(white: 1.0, alpha: 0.18)
    static let dangerColor = UIColor(hex: 0xFF2D55)
    static let textPrimary = UIColor(white: 1.0, alpha: 0.96)
    static let textSecondary = UIColor(white: 1.0, alpha: 0.55)
    static let accent = UIColor(hex: 0x00E5FF)
    static let feverA = UIColor(hex: 0xFF2D95)
    static let feverB = UIColor(hex: 0xFFB020)
    static let positive = UIColor(hex: 0x9BFF3C)

    // MARK: - Fonts

    static let fontHeavy = "AvenirNext-Heavy"
    static let fontBold = "AvenirNext-Bold"
    static let fontMedium = "AvenirNext-DemiBold"

    // MARK: - Chain banners

    /// Escalating praise for the size of a single detonated group. Size is the
    /// reward curve now, so this is the headline the player sees most often.
    static func blastTitle(size: Int, threshold: Int) -> String {
        switch size - threshold {
        case ..<2: return "BLAST"
        case 2..<5: return "BIG BLAST"
        case 5..<9: return "MASSIVE"
        case 9..<13: return "COLOSSAL"
        case 13..<18: return "MONSTROUS"
        default: return "SUPERNOVA"
        }
    }

    /// True once a blast is big enough to deserve the full screen treatment.
    static func isBigBlast(size: Int, threshold: Int) -> Bool {
        size - threshold >= 2
    }

    /// Escalating praise. Index is the chain depth, clamped.
    static func chainTitle(depth: Int) -> String {
        switch depth {
        case ..<2: return "BLAST"
        case 2: return "DOUBLE"
        case 3: return "TRIPLE"
        case 4: return "MASSIVE"
        case 5: return "INSANE"
        case 6: return "UNREAL"
        case 7: return "GODLIKE"
        default: return "COSMIC"
        }
    }

    static func streakTitle(_ streak: Int) -> String? {
        switch streak {
        case 3: return "STREAK ×3"
        case 5: return "ON FIRE"
        case 8: return "UNSTOPPABLE"
        case 12: return "LEGENDARY"
        default: return streak > 12 && streak % 5 == 0 ? "STREAK ×\(streak)" : nil
        }
    }
}

// MARK: - Colour helpers

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}

// MARK: - Small formatting helpers

extension Int {
    /// 12345 → "12,345"
    var grouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
