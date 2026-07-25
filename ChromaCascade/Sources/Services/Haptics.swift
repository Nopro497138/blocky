import UIKit

/// Thin wrapper over UIFeedbackGenerator. Generators are kept alive and prepared
/// so the taptic engine is warm when a cascade fires.
final class Haptics {

    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()

    private init() {}

    private var enabled: Bool { Storage.hapticsOn }

    func prepare() {
        guard enabled else { return }
        light.prepare()
        medium.prepare()
        heavy.prepare()
    }

    func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.6)
    }

    func place() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.8)
    }

    /// Escalates with the chain depth so a long cascade is felt, not just seen.
    func blast(chainStep: Int, cells: Int) {
        guard enabled else { return }
        let strength = min(1.0, 0.45 + Double(chainStep) * 0.15 + Double(cells) * 0.02)
        if strength > 0.85 {
            heavy.impactOccurred(intensity: CGFloat(strength))
        } else if strength > 0.6 {
            medium.impactOccurred(intensity: CGFloat(strength))
        } else {
            light.impactOccurred(intensity: CGFloat(strength))
        }
    }

    func fever() {
        guard enabled else { return }
        notify.notificationOccurred(.success)
    }

    func invalid() {
        guard enabled else { return }
        notify.notificationOccurred(.warning)
    }

    func gameOver() {
        guard enabled else { return }
        notify.notificationOccurred(.error)
    }
}
