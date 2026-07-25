import AVFoundation
import Foundation

/// All sound effects are procedurally generated WAVs (see `tools/make_audio.py`),
/// which keeps the repo self-contained and licence-free.
enum SoundID: String, CaseIterable {
    case uiTap = "ui_tap"
    case place = "place"
    case invalid = "invalid"
    case pickup = "pickup"
    case fall = "fall"
    case bomb = "bomb"
    case powerup = "powerup"
    case feverStart = "fever_start"
    case feverEnd = "fever_end"
    case gameOver = "game_over"
    case highScore = "high_score"
    case stageUp = "stage_up"
}

/// Loads every sound once and hands out a small round-robin pool of players per
/// sound, so overlapping blasts do not cut each other off.
final class AudioManager {

    static let shared = AudioManager()

    /// Blast tones climb a pentatonic scale; index = chain step.
    static let blastToneCount = 8

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var cursors: [String: Int] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var feverPlayer: AVAudioPlayer?
    private var configured = false

    private init() {}

    // MARK: - Setup

    func configure() {
        guard !configured else { return }
        configured = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        for id in SoundID.allCases {
            load(name: id.rawValue, copies: 2)
        }
        for i in 1...AudioManager.blastToneCount {
            load(name: "blast_\(i)", copies: 3)
        }

        musicPlayer = makeLoopingPlayer(named: "music_main", volume: 0.34)
        feverPlayer = makeLoopingPlayer(named: "music_fever", volume: 0.0)
    }

    private func load(name: String, copies: Int) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let data = try? Data(contentsOf: url) else { return }
        var players: [AVAudioPlayer] = []
        for _ in 0..<copies {
            if let player = try? AVAudioPlayer(data: data) {
                player.prepareToPlay()
                players.append(player)
            }
        }
        if !players.isEmpty {
            pools[name] = players
            cursors[name] = 0
        }
    }

    private func makeLoopingPlayer(named name: String, volume: Float) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.volume = volume
        player.prepareToPlay()
        return player
    }

    // MARK: - Effects

    private func play(name: String, volume: Float = 1.0, rate: Float = 1.0) {
        guard Storage.soundOn, let players = pools[name], !players.isEmpty else { return }
        let cursor = (cursors[name] ?? 0) % players.count
        cursors[name] = cursor + 1
        let player = players[cursor]
        player.volume = volume
        if rate != 1.0 {
            player.enableRate = true
            player.rate = rate
        }
        player.currentTime = 0
        player.play()
    }

    func play(_ id: SoundID, volume: Float = 1.0) {
        play(name: id.rawValue, volume: volume)
    }

    /// One rung of a cascade. Later steps are louder and higher — the sound is
    /// the reward curve.
    func playBlast(step: Int, cells: Int) {
        let tone = min(AudioManager.blastToneCount, max(1, step + 1))
        let volume = min(1.0, 0.7 + Float(cells) * 0.02)
        play(name: "blast_\(tone)", volume: volume)
    }

    // MARK: - Music

    func startMusic() {
        guard Storage.musicOn else { return }
        musicPlayer?.volume = 0.34
        feverPlayer?.volume = 0
        if musicPlayer?.isPlaying != true { musicPlayer?.currentTime = 0; musicPlayer?.play() }
        if feverPlayer?.isPlaying != true { feverPlayer?.currentTime = 0; feverPlayer?.play() }
    }

    func stopMusic() {
        musicPlayer?.stop()
        feverPlayer?.stop()
    }

    /// Crossfades between the base loop and the fever loop. Both run in sync, so
    /// switching is a volume change rather than a restart.
    func setFever(_ active: Bool) {
        guard Storage.musicOn else { return }
        musicPlayer?.setVolume(active ? 0.0 : 0.34, fadeDuration: 0.45)
        feverPlayer?.setVolume(active ? 0.42 : 0.0, fadeDuration: 0.45)
    }

    func setMusicEnabled(_ on: Bool) {
        Storage.musicOn = on
        if on { startMusic() } else { stopMusic() }
    }

    func duckForGameOver() {
        musicPlayer?.setVolume(0.08, fadeDuration: 0.6)
        feverPlayer?.setVolume(0.0, fadeDuration: 0.6)
    }
}
