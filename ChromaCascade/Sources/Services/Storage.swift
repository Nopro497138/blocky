import Foundation

/// Persisted stats and settings. Tiny on purpose — UserDefaults is plenty.
enum Storage {

    private enum Key {
        static let highScore = "cc.highScore"
        static let bestChain = "cc.bestChain"
        static let bestStreak = "cc.bestStreak"
        static let gamesPlayed = "cc.gamesPlayed"
        static let totalBlasts = "cc.totalBlasts"
        static let soundOn = "cc.soundOn"
        static let musicOn = "cc.musicOn"
        static let hapticsOn = "cc.hapticsOn"
        static let seenTutorial = "cc.seenTutorial"
    }

    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.soundOn: true,
            Key.musicOn: true,
            Key.hapticsOn: true,
        ])
    }

    static var highScore: Int {
        get { defaults.integer(forKey: Key.highScore) }
        set { defaults.set(newValue, forKey: Key.highScore) }
    }

    static var bestChain: Int {
        get { defaults.integer(forKey: Key.bestChain) }
        set { defaults.set(newValue, forKey: Key.bestChain) }
    }

    static var bestStreak: Int {
        get { defaults.integer(forKey: Key.bestStreak) }
        set { defaults.set(newValue, forKey: Key.bestStreak) }
    }

    static var gamesPlayed: Int {
        get { defaults.integer(forKey: Key.gamesPlayed) }
        set { defaults.set(newValue, forKey: Key.gamesPlayed) }
    }

    static var totalBlasts: Int {
        get { defaults.integer(forKey: Key.totalBlasts) }
        set { defaults.set(newValue, forKey: Key.totalBlasts) }
    }

    static var soundOn: Bool {
        get { defaults.bool(forKey: Key.soundOn) }
        set { defaults.set(newValue, forKey: Key.soundOn) }
    }

    static var musicOn: Bool {
        get { defaults.bool(forKey: Key.musicOn) }
        set { defaults.set(newValue, forKey: Key.musicOn) }
    }

    static var hapticsOn: Bool {
        get { defaults.bool(forKey: Key.hapticsOn) }
        set { defaults.set(newValue, forKey: Key.hapticsOn) }
    }

    static var seenTutorial: Bool {
        get { defaults.bool(forKey: Key.seenTutorial) }
        set { defaults.set(newValue, forKey: Key.seenTutorial) }
    }

    /// Folds a finished run into the persisted records. Returns true for a new best.
    @discardableResult
    static func recordRun(score: Int, bestChain chain: Int, bestStreak streak: Int, blasts: Int) -> Bool {
        gamesPlayed += 1
        totalBlasts += blasts
        bestChain = max(bestChain, chain)
        bestStreak = max(bestStreak, streak)
        if score > highScore {
            highScore = score
            return true
        }
        return false
    }
}
