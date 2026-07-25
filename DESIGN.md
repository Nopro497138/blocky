# Chroma Cascade — Game Design Document

**Genre:** Block puzzle / colour-chain arcade
**Platform:** iOS 15+ (iPhone, portrait)
**Tech:** Swift + SpriteKit, no third-party dependencies
**Session length:** ~3–5 minutes per run

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
| Reward | fixed per line | **quadratic in group size — big blobs pay enormously** |
| Difficulty | static | **8 stages: more colours, larger groups required** |
| Skill ceiling | packing efficiency | packing **+ colour planning to grow one huge cluster** |

The dopamine loop is the *big blast*: you spend a dozen turns feeding one
colour into a single growing blob, resisting the urge to cash it in, and then
detonate twenty blocks at once while the tone climbs a pentatonic scale, the
screen shakes and the banner reads SUPERNOVA.

---

## 2. Core loop

1. Three pieces sit in the tray. Each is a small polyomino in **one** colour.
2. Drag a piece onto the board. A ghost preview shows the exact cells it will
   occupy; it locks **exactly where you drop it** — nothing slides.
3. **Resolve:** every orthogonally connected group of ≥ `threshold` same-colour
   cells detonates simultaneously.
4. **Aftershock:** every surviving cell falls down its column.
5. If the landing formed another big enough group **of the same colour** →
   detonate again with `chain += 1`. Each rung scores harder.
6. Tray empty → refill with three new pieces.
7. **Game over** when none of the tray pieces fits anywhere *and* no power-up
   charge is left.

### 2.1 Blasts are colour-honest, and size is the reward

Two rules do the heavy lifting:

1. **A cascade stays inside the colour that started it.** A follow-up rung can
   only detonate more of the *same* colour.
2. **A follow-up rung needs one cell fewer than the opening one**, not a flat
   small number.

An earlier build had follow-up rungs fire at 3 cells of *any* colour. At stage 7
— where starting a blast asks for 9 cells — that meant one placement could
unravel clumps of all six colours in sequence. It played like the board falling
apart on its own, and it made the game trivially easy. See §8.4.

The consequence is that **group size, not chain depth, is the thing to chase.**
Scoring reflects that: the bonus for overshooting the requirement is quadratic,
so one 20-block blob is worth far more than four 5-block ones. Every feedback
channel — banner text, blast pitch, haptic strength, screen shake — scales with
overshoot rather than with rung count.

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
| 2 FLUX | 10 | 5 | 5 | 1–4 |
| 3 SURGE | 24 | 5 | 6 | 1–5 |
| 4 PRISM | 40 | 6 | 7 | 2–5 |
| 5 NOVA | 60 | 6 | 8 | 2–5 |
| 6 PULSAR | 85 | 6 | 9 | 3–5 |
| 7 QUASAR | 115 | 6 | 10 | 3–5 |
| 8 SINGULARITY | 150 | 6 | 11 | 4–5 |

Score was tried as the clock first and had to be abandoned: players plateau at
exactly the score where their skill stops paying, so the stage stops advancing
and the run never ends (§8.2). Turn count escalates unconditionally, so skill
converts into *score*, not into immortality, and every run builds to a climax.

Follow-up rungs always ask for one cell fewer than the opening requirement, at
every stage — cascades never become the cheap option.

## 5. Scoring

```
groupScore  = 10·n + 6·max(0, n − t)²        n = cells, t = threshold of the rung
stepScore   = Σ groupScore over all groups in the rung
chainMult   = [1, 1.6, 2.4, 3.6, 5.2, 7.5, 10, 14, 19, 25]  (clamped at the last)
simultaneity= 1 + 0.25 · (groups in this rung − 1)
turnScore   = Σ stepScore · chainMult[rung] · simultaneity · feverMult
```

## 6. Heat & Fever

* A placement that detonates anything adds `1 + chainDepth` heat; one that does
  not drains `0.5`. At **10** heat → **FEVER**.
* Fever lasts 8 placements, extended by 2 for every blast during it, and:
  * **triples** all score,
  * restricts the tray to the **two colours the board already holds most of**,
  * switches the music, pulses the background magenta/amber, recolours the board
    frame.
* Fever deliberately does **not** lower the blast requirement. That was the
  original design and it was wrong: blasting became automatic, the board cleared
  itself, and the player stopped mattering during the most exciting part of the
  run. Narrowing the palette instead turns fever into an *opportunity* — the
  game hands you the material to assemble one enormous cluster, and you still
  have to place it.
* Fever ends at heat 8 rather than 0, so re-entry stays reachable.

Measured: ~3 Fever phases per run for the human proxy.

## 7. Power-ups (earned, never bought)

| Power-up | Earned | Effect |
|---|---|---|
| **Bomb** | every 4 000 points | tap a cell → 3×3 destroyed, then cascades normally |
| **Reroll** | every 6 000 points | replaces all three tray pieces |
| **Hint** | free, once per 4 placements | highlights the strongest placement available |

The hint runs the real `CascadeResolver` on a copy of the board, so it can never
suggest something the game would score differently. It is rate-limited on
purpose: an always-available perfect suggestion plays the game for the player.

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

### 8.4 Cheap any-colour follow-up rungs → the board dissolves itself

The build below (§8.3) shipped with follow-up rungs fixed at 3 cells, matching
*any* colour. Playtesting showed what the simulator's aggregate numbers had
hidden: the "deep chains" it produced were not built by the player at all. At
the late stages the gap between the opening requirement (9–11) and the
follow-up (3) was so wide that one placement set off a self-sustaining
demolition across every colour, and fever — which lowered the opening
requirement too — made it near-continuous.

Fixing it (same colour only, follow-up = opening − 1) cut chains of depth ≥ 3
from ~5 per run to ~0.1. That is not a regression: it is the measurement of how
much of the old spectacle was unearned. The reward moved to group size, which is
the thing this rule set actually lets a player build deliberately.

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
| median run length | 100–150 placements | **115** |
| runs that never end | 0 % | **0 %** |
| placements that detonate something | 30–45 % | **33 %** |
| blasts of 10+ cells per run | 5–12 | **9.2** |
| blasts of 15+ cells per run | rare, memorable | **0.4** |
| Fever entries per run | 1–4 | **3** |
| random-player floor | should die fast | **50 placements** |
| expert (1-ply search) | should last, still die | **245 median, 0 immortal** |
