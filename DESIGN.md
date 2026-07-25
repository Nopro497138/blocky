# Chroma Cascade — Game Design Document

**Genre:** Block puzzle / colour-chain arcade
**Platform:** iOS 15+ (iPhone, portrait)
**Tech:** Swift + SpriteKit, no third-party dependencies
**Session length:** ~4–7 minutes per run

---

## 1. The hook (and how it differs from Block Blast)

Block Blast is: drag polyominoes onto an 8×8 grid; fill a complete row or
column and it clears. No colour logic, no gravity, no chains.

**Chroma Cascade** keeps the tactile "drag a block shape onto a grid" feel and
the 2D packing puzzle, but replaces the entire clearing rule:

| | Block Blast | **Chroma Cascade** |
|---|---|---|
| Clear condition | complete row/column | **5+ connected cells of the same colour** |
| Colour | cosmetic | **the core mechanic** |
| Gravity | none | **only as the aftershock of a detonation** |
| Chains | impossible | **cascades: a blast drops blocks, forming new groups → ×1.4, ×2, ×3 …** |
| Difficulty | static | **8 stages: more colours, larger groups required** |
| Skill ceiling | packing efficiency | packing **+ colour planning for multi-chains** |

The dopamine loop is the *cascade*: you build a colour structure over several
turns, then one placement detonates a four-step chain that eats half the board
while the blast tone climbs a pentatonic scale and the screen shakes.

---

## 2. Core loop

1. Three pieces sit in the tray. Each is a small polyomino in **one** colour.
2. Drag a piece onto the board. A ghost preview shows the exact cells it will
   occupy; it locks **exactly where you drop it** — nothing slides.
3. **Resolve:** every orthogonally connected group of ≥ `threshold` same-colour
   cells detonates simultaneously.
4. **Aftershock:** every surviving cell falls down its column.
5. If the landing formed a group of ≥ 3 same-colour cells → detonate again with
   `chain += 1`. Each rung scores harder, sounds higher and shakes more.
6. Tray empty → refill with three new pieces.
7. **Game over** when none of the tray pieces fits anywhere *and* no power-up
   charge is left.

### 2.1 The two thresholds — the most important rule in the game

Starting a blast needs a **big** group (5, rising to 10 by the last stage).
Continuing a cascade needs only **3**.

Fiction: the shockwave destabilises smaller clusters. Function: it decouples
*pressure* from *payoff*. A single threshold cannot do both — see §8.

### 2.2 Placement locks, blasts pull

Placing a piece does not move anything; detonating does. This is deliberately
asymmetric, and it is what lets one game contain both a Block-Blast-style
packing puzzle and Puyo-style cascades:

* if gravity applied on placement too, the player would only ever choose a
  *column*, and a competent player could keep the board empty forever (§8.1);
* if gravity never applied, cascades could not exist at all.

---

## 3. Board & pieces

* Board: **8 columns × 10 rows**. The top 2 rows are the danger zone and pulse
  red once the stack reaches them.
* Pieces are polyominoes of 1–5 cells, no rotation (all useful rotations exist
  as separate shapes in the pool). Spawn weights favour 2–4 cell pieces.
* Later stages remove the small pieces from the pool and add the 5-cell ones,
  which tightens the board without changing any rule the player has to relearn.

## 4. Difficulty: the clock is turn count, not score

| Stage | From turn | Colours | Cells to blast | Piece sizes |
|---|---|---|---|---|
| 1 SPARK | 0 | 4 | 5 | 1–4 |
| 2 FLUX | 15 | 5 | 5 | 1–4 |
| 3 SURGE | 35 | 5 | 6 | 1–5 |
| 4 PRISM | 60 | 6 | 6 | 2–5 |
| 5 NOVA | 85 | 6 | 7 | 2–5 |
| 6 PULSAR | 115 | 6 | 8 | 3–5 |
| 7 QUASAR | 150 | 6 | 9 | 3–5 |
| 8 SINGULARITY | 200 | 6 | 10 | 4–5 |

Score was tried as the clock first and had to be abandoned: players plateau at
exactly the score where their skill stops paying, so the stage stops advancing
and the run never ends (§8.2). Turn count escalates unconditionally, so skill
converts into *score*, not into immortality, and every run builds to a climax.

The chain threshold stays at **3** for the whole game. Cascades are the reward;
they never get harder.

## 5. Scoring

```
groupScore  = 10·n + 5·max(0, n − t)²        n = cells, t = threshold of the rung
stepScore   = Σ groupScore over all groups in the rung
chainMult   = [1, 1.4, 2, 3, 4.5, 6.5, 9, 12, 16, 21]   (clamped at the last)
simultaneity= 1 + 0.25 · (groups in this rung − 1)
turnScore   = Σ stepScore · chainMult[rung] · simultaneity · feverMult
```

## 6. Heat & Fever

* A placement that detonates anything adds `1 + chainDepth` heat; one that does
  not drains `0.5`. At **10** heat → **FEVER**.
* Fever lasts 8 placements, extended by 2 for every blast during it, and:
  * takes **2 cells off** the blast requirement (never below chain threshold+1),
  * doubles all score,
  * switches the music, pulses the background magenta/amber, recolours the board
    frame.
* Fever ends at heat 8 rather than 0, so re-entry stays reachable.

Measured: ~3.5 Fever phases per run for the human proxy.

## 7. Power-ups (earned, never bought)

| Power-up | Earned | Effect |
|---|---|---|
| **Bomb** | every 6 000 points | tap a cell → 3×3 destroyed, then cascades normally |
| **Reroll** | every 9 000 points | replaces all three tray pieces |

Max 3 charges each. **A stored charge also defers death:** running out of moves
is only fatal with an empty inventory. Being rescued at the last second by a
bomb is a better beat than a sudden loss.

No IAP, no ads, no timers.

## 8. Rules that were tried and thrown away

The rule set was simulated before any Swift was written
(`tools/simulate.js`, ~150 runs per candidate, three policies: random, a
"human proxy" sampling 30 % of legal placements, and a 1-ply full-search
expert). Three versions died in that harness:

### 8.1 Gravity on every placement → unlosable

First version: pieces fell to the bottom, the player chose a column (Puyo-like).
Result: **100 % of expert runs and most human-proxy runs never ended** — capped
at 800 placements. With free column choice and no time pressure, clears outpace
placements forever. Every board size, colour count and threshold in the sweep
had the same failure. Cell-level gravity keeps the board self-cleaning; the
genre only gets away with it under time pressure or opponent garbage, neither of
which fits a relaxed single-player puzzle.

### 8.2 Score as the difficulty clock → runs stall

Second version: stages advanced by score. Players converge on the score where
their skill stops paying, the stage stops advancing, and the run becomes
infinite: **89 % of human-proxy runs hit the placement cap, all of them parked
in stage 4.** Turn count fixed it outright.

### 8.3 A single threshold → either no pressure or no chains

With one threshold for both starting and continuing:

* threshold 5 → 60 % of placements blast, board never fills, unlosable;
* threshold 7 → 20 % blast, board fills, but **0.2–1.3 chains of depth ≥ 3 per
  entire run** — the cascade the game is named after basically never happened.

Splitting it (5–10 to start, 3 to continue) produced 3–12 deep chains per run
*and* a board that fills. That single change is what made the concept work.

## 9. Feedback / "juice"

* **Place:** slam with squash, tick, rigid haptic.
* **Blast:** cells flash white, scale up, shatter into additive particles in
  their own colour; radial flash; shockwave ring from rung 2; screen shake
  scaled by rung and group size; haptic strength scaled the same way.
* **Chain:** blast tone climbs a C-major pentatonic scale, one step per rung
  (`blast_1..8.wav`), plus a banner — BLAST → DOUBLE → TRIPLE → MASSIVE →
  INSANE → UNREAL → GODLIKE → COSMIC — and a camera zoom punch.
* **Score:** rolling count-up in the HUD and floating `+1,240` popups from the
  blast centroid.
* **Fever:** screen flash, palette wash, music crossfade (the two loops are
  8.571 s each — 112 BPM × 4 bars == 140 BPM × 5 bars — so they never drift).
* **Near death:** danger line and vignette pulse; unplayable tray pieces dim.
* **Game over:** the board drains row by row before the panel appears; a new
  best triggers confetti.

## 10. Balance targets vs. measured

Human proxy, 150 runs, final configuration:

| Metric | Target | Measured |
|---|---|---|
| median run length | 60–200 placements | **204** |
| runs that never end | 0 % | **0 %** |
| placements that detonate something | 30–50 % | **33 %** |
| chains of depth ≥ 3 per run | 3–10 | **5** |
| Fever entries per run | 1–4 | **3.5** |
| random-player floor | should die fast | **104 placements** |
| expert (1-ply search) | should last, still die | **347 median, 0 immortal** |
