import Foundation

/// Launch-argument hooks used by the CI smoke test (`scripts/smoke-test.sh`) to
/// boot the game in a known state and screenshot it.
///
/// These are inert in normal use — a user cannot pass launch arguments to an
/// installed app — but they are what makes it possible to verify that the game
/// actually runs and renders, rather than only that it compiles.
enum DebugOptions {

    private static let arguments = ProcessInfo.processInfo.arguments

    /// `--cc-scene-game` skips the menu and starts a run immediately.
    static var startsInGame: Bool {
        arguments.contains("--cc-scene-game")
    }

    /// `--cc-autoplay 24` plays 24 automatic placements after launch.
    static var autoplayMoves: Int {
        value(for: "--cc-autoplay").flatMap(Int.init) ?? 0
    }

    /// `--cc-seed 12345` makes a run reproducible, so screenshots are stable.
    static var seed: UInt64? {
        value(for: "--cc-seed").flatMap(UInt64.init)
    }

    private static func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
