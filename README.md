# Chroma Cascade

A neon block puzzle for iOS. You drag block shapes onto a grid like you would in
Block Blast — but nothing clears by filling a row. **Colour** is the mechanic:

> Connect **5+ blocks of one colour** and the whole group detonates. Everything
> above the hole falls down, and the cascade continues **only in that same
> colour**.

Scoring grows with the *square* of the group size, so the game is a race to
assemble one enormous single-colour blob before the board fills. A 20-block
detonation is worth more than four 5-block ones — and the banner, the blast
pitch, the haptics and the screen shake all scale with how big you managed to
build it.

Built in Swift + SpriteKit, no third-party dependencies, no ads, no IAP.

---

## The loop

| | |
|---|---|
| **Board** | 8 × 10 |
| **Tray** | 3 pieces, refills when all three are used |
| **Placement** | pieces lock exactly where you drop them — gravity only applies as the aftershock of a detonation |
| **Blast** | 5+ connected same-colour cells (rises to 11 in the last stage) |
| **Chain** | continues only in the colour that started it, and needs one cell fewer than the opening |
| **Heat / Fever** | blasts fill a meter; Fever = ×3 score and the tray narrows to your 2 most common colours for 8 moves |
| **Stages** | every 10–35 placements: more colours, bigger groups required, chunkier pieces |
| **Power-ups** | Bomb (3×3) and Reroll, earned by score — and they rescue you from an otherwise fatal dead end |
| **Hint** | free every 4 placements: ranks every legal placement and highlights the best one |
| **Game over** | when no tray piece fits anywhere and you have no charges left |

Full design rationale, including why the first two versions of the rule set were
thrown away, is in [DESIGN.md](DESIGN.md).

---

## Getting the .ipa

### Option A — GitHub Actions (already set up)

Every push to `main` or `claude/**` runs `.github/workflows/ios.yml` on a macOS
runner and uploads **`ChromaCascade-unsigned-ipa`** as a build artifact.
Actions → latest run → Artifacts.

### Option B — Codemagic

`codemagic.yaml` defines two workflows:

* **`ios-unsigned`** — the default. No Apple Developer account, no certificates,
  no integrations. Connect the repo in Codemagic, start the build, download
  `build/ChromaCascade-unsigned.ipa`.
* **`ios-signed`** — only once you have a $99/yr Apple Developer membership.
  Add an App Store Connect API key in Codemagic under the integration name
  `codemagic`, register the bundle id `com.chromacascade.game`, then run it.
  This one can also push straight to TestFlight.

### Option C — locally on a Mac

```bash
brew install xcodegen
./scripts/build-unsigned-ipa.sh     # → build/ChromaCascade-unsigned.ipa
```

Or just `xcodegen generate && open ChromaCascade.xcodeproj`.

---

## Installing an unsigned .ipa on your iPhone

An unsigned .ipa cannot be installed by tapping it — it has to be signed with
*some* Apple ID first. That is what these tools do, and a **free** Apple ID is
enough:

1. **[Sideloadly](https://sideloadly.io)** (Windows/macOS) or
   **[AltStore](https://altstore.io)** (needs AltServer running on a computer).
2. Plug the iPhone in, drop in the `.ipa`, sign in with your Apple ID.
3. On the phone: *Settings → General → VPN & Device Management* → trust the
   developer profile.

Free-account caveats, so there are no surprises:

* the app **expires after 7 days** and must be re-signed (AltStore can refresh
  it automatically over Wi-Fi),
* max 3 sideloaded apps at a time,
* the phone must be able to reach the signing computer to refresh.

With a paid developer account, signed builds last a year and TestFlight installs
need no computer at all — that is what the `ios-signed` workflow is for.

---

## Repository layout

```
ChromaCascade/
  Sources/
    App/            AppDelegate, GameViewController
    Engine/         pure game logic — no SpriteKit, no UIKit, deterministic
    Presentation/   SpriteKit scenes, nodes, textures, effects
    Services/       audio, haptics, persistence
  Resources/
    Audio/          22 procedurally generated WAVs
    Assets.xcassets app icon + launch colour
tools/
  simulate.js       balance simulator (mirrors the Swift engine)
  sweep.js          config sweep across board sizes / thresholds / piece pools
  make_audio.py     synthesises every sound effect and both music loops
  make_icon.py      renders the app icon set (no imaging library required)
scripts/
  build-unsigned-ipa.sh
project.yml         XcodeGen spec — the .xcodeproj is generated, never committed
```

## Regenerating the assets

Both generators are deterministic; the committed output is exactly what they
produce.

```bash
python3 tools/make_audio.py    # ~2 s  → ChromaCascade/Resources/Audio/*.wav
python3 tools/make_icon.py     # ~5 s  → AppIcon.appiconset/*.png
```

## Re-tuning the balance

The rule set was tuned by simulation before any Swift was written, against three
policies: a random player (floor), a "human proxy" that samples ~30 % of the
legal placements with a shallow heuristic, and a 1-ply full-search expert.

```bash
node tools/simulate.js 150     # run distributions for all three policies
node tools/sweep.js 40         # sweep board size / thresholds / piece pools
```

Current numbers for the human proxy: median 115 placements per run, 33 % of
placements detonate something, ~9 blasts of 10+ blocks and ~3 Fever phases per
run, and 0 % of runs fail to terminate for any policy. Change `CFG` in `tools/simulate.js` and
mirror the winning values into `ChromaCascade/Sources/Engine/GameConfig.swift`.
