#!/usr/bin/env node
/*
 * Chroma Cascade — balance simulator.
 *
 * Mirrors the Swift engine rules exactly so that board size, group threshold,
 * piece weights, colour count, scoring curve and fever thresholds can be tuned
 * before a single line of Swift is written.
 *
 * Usage: node tools/simulate.js [runs] [--json]
 */

'use strict';

// ---------------------------------------------------------------- configuration

const CFG = {
  // 'drop' = piece falls to the bottom (Puyo-like, column choice only)
  // 'free' = piece locks exactly where dropped (Block Blast-like 2D placement);
  //          gravity then applies only as the aftershock of a detonation
  mode: 'free',
  cols: 8,
  rows: 10,
  dangerRows: 2,
  baseThreshold: null, // null = driven by the stage table below
  chainThreshold: 3,
  feverHeatNeeded: 10,
  feverHeatDrain: 0.5,
  feverPlacements: 8,
  feverExtendPerBlast: 2,
  feverHeatAfter: 8,
  chainMult: [1, 1.4, 2, 3, 4.5, 6.5, 9, 12, 16, 21],
  simultaneityBonus: 0.25,
  safetyCap: 4000,
  // Placements are the difficulty clock. Score cannot be the clock: players
  // plateau at exactly the score where their skill stops paying, and the run
  // then never ends. Turn count escalates unconditionally, so every run builds
  // to a climax and ends — skill converts into score, not into immortality.
  stages: [
    { turn: 0, colors: 4, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 15, colors: 5, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 35, colors: 5, threshold: 6, minPiece: 1, maxPiece: 5 },
    { turn: 60, colors: 6, threshold: 6, minPiece: 2, maxPiece: 5 },
    { turn: 85, colors: 6, threshold: 7, minPiece: 2, maxPiece: 5 },
    { turn: 115, colors: 6, threshold: 8, minPiece: 3, maxPiece: 5 },
    { turn: 150, colors: 6, threshold: 9, minPiece: 3, maxPiece: 5 },
    { turn: 200, colors: 6, threshold: 10, minPiece: 4, maxPiece: 5 },
  ],
};

// Pieces: list of [row, col] cells, normalised to min 0. `w` = spawn weight.
const PIECES = [
  { id: 'dot', w: 4, cells: [[0, 0]] },
  { id: 'duo-h', w: 10, cells: [[0, 0], [0, 1]] },
  { id: 'duo-v', w: 10, cells: [[0, 0], [1, 0]] },
  { id: 'tri-h', w: 8, cells: [[0, 0], [0, 1], [0, 2]] },
  { id: 'tri-v', w: 8, cells: [[0, 0], [1, 0], [2, 0]] },
  { id: 'corner-a', w: 7, cells: [[0, 0], [1, 0], [1, 1]] },
  { id: 'corner-b', w: 7, cells: [[0, 0], [0, 1], [1, 1]] },
  { id: 'corner-c', w: 7, cells: [[0, 1], [1, 0], [1, 1]] },
  { id: 'corner-d', w: 7, cells: [[0, 0], [0, 1], [1, 0]] },
  { id: 'square', w: 9, cells: [[0, 0], [0, 1], [1, 0], [1, 1]] },
  { id: 'quad-h', w: 4, cells: [[0, 0], [0, 1], [0, 2], [0, 3]] },
  { id: 'quad-v', w: 4, cells: [[0, 0], [1, 0], [2, 0], [3, 0]] },
  { id: 'tee', w: 5, cells: [[0, 0], [0, 1], [0, 2], [1, 1]] },
  { id: 'ell', w: 5, cells: [[0, 0], [1, 0], [2, 0], [2, 1]] },
  { id: 'jay', w: 5, cells: [[0, 1], [1, 1], [2, 1], [2, 0]] },
  { id: 'ess', w: 4, cells: [[0, 1], [0, 2], [1, 0], [1, 1]] },
  { id: 'zee', w: 4, cells: [[0, 0], [0, 1], [1, 1], [1, 2]] },
  { id: 'penta-h', w: 2, cells: [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]] },
  { id: 'penta-p', w: 3, cells: [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0]] },
];

// ---------------------------------------------------------------- rng

function makeRng(seed) {
  let s = seed >>> 0;
  return function () {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

// ---------------------------------------------------------------- board helpers

function emptyBoard() {
  return new Int8Array(CFG.cols * CFG.rows);
}
const idx = (r, c) => r * CFG.cols + c;

function pieceBounds(cells) {
  let h = 0, w = 0;
  for (const [r, c] of cells) { if (r + 1 > h) h = r + 1; if (c + 1 > w) w = c + 1; }
  return { h, w };
}

/** Resting row offset for a rigid piece dropped at column offset x, or null if it cannot rest on-board. */
function restingOffset(board, cells, x) {
  const { h, w } = pieceBounds(cells);
  if (x < 0 || x + w > CFG.cols) return null;
  let d = -h; // fully above the board
  for (;;) {
    const next = d + 1;
    let blocked = false;
    for (const [r, c] of cells) {
      const rr = r + next, cc = c + x;
      if (rr >= CFG.rows) { blocked = true; break; }
      if (rr >= 0 && board[idx(rr, cc)] !== 0) { blocked = true; break; }
    }
    if (blocked) break;
    d = next;
  }
  if (d < 0) return null; // part of the piece would lock above the board → invalid
  for (const [r] of cells) if (r + d < 0) return null;
  return d;
}

function applyGravity(board) {
  let moved = false;
  for (let c = 0; c < CFG.cols; c++) {
    let write = CFG.rows - 1;
    for (let r = CFG.rows - 1; r >= 0; r--) {
      const v = board[idx(r, c)];
      if (v !== 0) {
        if (write !== r) { board[idx(write, c)] = v; board[idx(r, c)] = 0; moved = true; }
        write--;
      }
    }
  }
  return moved;
}

/** All orthogonally connected same-colour groups of at least `threshold` cells. */
function findGroups(board, threshold) {
  const seen = new Uint8Array(CFG.cols * CFG.rows);
  const groups = [];
  const stack = [];
  for (let r = 0; r < CFG.rows; r++) {
    for (let c = 0; c < CFG.cols; c++) {
      const i = idx(r, c);
      if (seen[i] || board[i] === 0) continue;
      const color = board[i];
      const group = [];
      stack.length = 0;
      stack.push(i);
      seen[i] = 1;
      while (stack.length) {
        const cur = stack.pop();
        group.push(cur);
        const cr = (cur / CFG.cols) | 0, cc = cur % CFG.cols;
        if (cr > 0) pushIf(cr - 1, cc);
        if (cr < CFG.rows - 1) pushIf(cr + 1, cc);
        if (cc > 0) pushIf(cr, cc - 1);
        if (cc < CFG.cols - 1) pushIf(cr, cc + 1);
      }
      if (group.length >= threshold) groups.push(group);

      function pushIf(nr, nc) {
        const ni = idx(nr, nc);
        if (!seen[ni] && board[ni] === color) { seen[ni] = 1; stack.push(ni); }
      }
    }
  }
  return groups;
}

function groupScore(n, t) {
  const over = n - t;
  return 10 * n + 5 * (over > 0 ? over * over : 0);
}

function chainMult(step) {
  const m = CFG.chainMult;
  return step < m.length ? m[step] : m[m.length - 1];
}

/**
 * Runs the full detonation cascade.
 *
 * The first step needs a full-size group (`threshold`) — that is the pressure
 * valve. Every follow-up step of the same cascade only needs `chainThreshold`
 * cells, because the shockwave destabilises smaller clusters. That asymmetry is
 * what turns one good placement into a five-step board-eating chain.
 */
function resolve(board, threshold, feverMult) {
  let step = 0, total = 0, cleared = 0;
  for (;;) {
    const t = step === 0 ? threshold : Math.min(threshold, CFG.chainThreshold);
    const groups = findGroups(board, t);
    if (groups.length === 0) break;
    let stepScore = 0;
    for (const g of groups) {
      stepScore += groupScore(g.length, t);
      cleared += g.length;
      for (const i of g) board[i] = 0;
    }
    const simult = 1 + CFG.simultaneityBonus * (groups.length - 1);
    total += stepScore * chainMult(step) * simult * feverMult;
    applyGravity(board);
    step++;
    if (step > 64) break; // safety
  }
  return { score: Math.round(total), chainDepth: step, cleared };
}

function stackHeight(board) {
  for (let r = 0; r < CFG.rows; r++) {
    for (let c = 0; c < CFG.cols; c++) if (board[idx(r, c)] !== 0) return CFG.rows - r;
  }
  return 0;
}

function holes(board) {
  let n = 0;
  for (let c = 0; c < CFG.cols; c++) {
    let seenBlock = false;
    for (let r = 0; r < CFG.rows; r++) {
      if (board[idx(r, c)] !== 0) seenBlock = true;
      else if (seenBlock) n++;
    }
  }
  return n;
}

// ---------------------------------------------------------------- game

function stageForTurn(turn) {
  let out = CFG.stages[0], i = 0, level = 0;
  for (const s of CFG.stages) { if (turn >= s.turn) { out = s; level = i; } i++; }
  return { stage: out, level };
}

function activePieces(stage) {
  const max = CFG.maxPieceSize || stage.maxPiece;
  const min = CFG.minPieceSize || stage.minPiece;
  return PIECES.filter((p) => p.cells.length <= max && p.cells.length >= min);
}

function makePiece(rng, stage) {
  const colors = stage.colors;
  const pool = activePieces(stage);
  let totalW = 0;
  for (const p of pool) totalW += p.w;
  let roll = rng() * totalW;
  let def = pool[pool.length - 1];
  for (const p of pool) { roll -= p.w; if (roll <= 0) { def = p; break; } }
  return { cells: def.cells, color: 1 + Math.floor(rng() * colors), id: def.id };
}

/** True if the piece fits with its origin at (d, x) with every cell on an empty square. */
function fitsAt(board, cells, d, x) {
  for (const [r, c] of cells) {
    const rr = r + d, cc = c + x;
    if (rr < 0 || rr >= CFG.rows || cc < 0 || cc >= CFG.cols) return false;
    if (board[idx(rr, cc)] !== 0) return false;
  }
  return true;
}

function legalMoves(board, piece) {
  const { h, w } = pieceBounds(piece.cells);
  const out = [];
  if (CFG.mode === 'drop') {
    for (let x = 0; x + w <= CFG.cols; x++) {
      const d = restingOffset(board, piece.cells, x);
      if (d !== null) out.push({ x, d });
    }
  } else {
    for (let d = 0; d + h <= CFG.rows; d++) {
      for (let x = 0; x + w <= CFG.cols; x++) {
        if (fitsAt(board, piece.cells, d, x)) out.push({ x, d });
      }
    }
  }
  return out;
}

function place(board, piece, x, d) {
  for (const [r, c] of piece.cells) board[idx(r + d, c + x)] = piece.color;
}

function playRun(seed, policy) {
  const rng = makeRng(seed);
  const board = emptyBoard();
  let score = 0, placements = 0, streak = 0, bestStreak = 0, heat = 0;
  let feverLeft = 0, feverEntries = 0, blastPlacements = 0;
  let bestChain = 0, maxLevel = 0;
  const chainHist = {};
  let stage = CFG.stages[0];
  let tray = [makePiece(rng, stage), makePiece(rng, stage), makePiece(rng, stage)];

  for (;;) {
    const st = stageForTurn(placements);
    if (st.level > maxLevel) maxLevel = st.level;
    const base = CFG.baseThreshold || st.stage.threshold;
    // Fever has to feel like a superpower, so it takes two cells off the
    // requirement, never dropping below the chain threshold + 1.
    const threshold = feverLeft > 0 ? Math.max(CFG.chainThreshold + 1, base - 2) : base;
    const feverMult = feverLeft > 0 ? 2 : 1;

    // gather every legal (pieceIndex, x)
    const options = [];
    for (let i = 0; i < tray.length; i++) {
      if (!tray[i]) continue;
      for (const m of legalMoves(board, tray[i])) options.push({ i, x: m.x, d: m.d });
    }
    if (options.length === 0) break; // game over

    const choice = policy(board, tray, options, threshold, feverMult, rng);

    const piece = tray[choice.i];
    place(board, piece, choice.x, choice.d);
    tray[choice.i] = null;
    const res = resolve(board, threshold, feverMult);
    score += res.score;
    placements++;
    if (res.chainDepth > 0) {
      blastPlacements++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
      heat += 1 + res.chainDepth;
      if (res.chainDepth > bestChain) bestChain = res.chainDepth;
      chainHist[res.chainDepth] = (chainHist[res.chainDepth] || 0) + 1;
      if (feverLeft > 0) feverLeft += CFG.feverExtendPerBlast;
    } else {
      streak = 0;
      heat = Math.max(0, heat - CFG.feverHeatDrain);
    }
    if (feverLeft > 0) {
      feverLeft--;
      if (feverLeft === 0) heat = CFG.feverHeatAfter;
    } else if (heat >= CFG.feverHeatNeeded) {
      feverLeft = CFG.feverPlacements;
      feverEntries++;
      heat = 0;
    }

    if (tray.every((p) => p === null)) {
      stage = stageForTurn(placements).stage;
      tray = [makePiece(rng, stage), makePiece(rng, stage), makePiece(rng, stage)];
    }
    if (placements >= CFG.safetyCap) break; // safety for degenerate policies
  }

  return { score, placements, bestChain, bestStreak, feverEntries, blastPlacements, chainHist, maxLevel };
}

// ---------------------------------------------------------------- policies

const randomPolicy = (board, tray, options, threshold, feverMult, rng) =>
  options[Math.floor(rng() * options.length)];

/** Empty cells that have no empty orthogonal neighbour — the board's dead space. */
function deadSpace(board) {
  let n = 0;
  for (let r = 0; r < CFG.rows; r++) {
    for (let c = 0; c < CFG.cols; c++) {
      if (board[idx(r, c)] !== 0) continue;
      let free = 0;
      if (r > 0 && board[idx(r - 1, c)] === 0) free++;
      if (r < CFG.rows - 1 && board[idx(r + 1, c)] === 0) free++;
      if (c > 0 && board[idx(r, c - 1)] === 0) free++;
      if (c < CFG.cols - 1 && board[idx(r, c + 1)] === 0) free++;
      if (free === 0) n += 3;
      else if (free === 1) n += 1;
    }
  }
  return n;
}

function occupancy(board) {
  let n = 0;
  for (let i = 0; i < board.length; i++) if (board[i] !== 0) n++;
  return n;
}

/** Rough stand-in for a competent human: value points, keep the board open. */
function greedyPolicy(board, tray, options, threshold, feverMult) {
  let best = null, bestVal = -Infinity;
  for (const o of options) {
    const copy = Int8Array.from(board);
    place(copy, tray[o.i], o.x, o.d);
    const res = resolve(copy, threshold, feverMult);
    let val = res.score + res.cleared * 8;
    if (CFG.mode === 'drop') {
      val += -stackHeight(copy) * 22 - holes(copy) * 14;
    } else {
      val += -occupancy(copy) * 4 - deadSpace(copy) * 6;
    }
    // small bonus for building same-colour neighbourhoods (setting chains up)
    val += adjacencyBonus(copy, tray[o.i], o.x, o.d);
    if (val > bestVal) { bestVal = val; best = o; }
  }
  return best;
}

/**
 * Proxy for an average human: only glances at a fraction of the possible
 * placements, weights the immediate blast far above board hygiene, and
 * occasionally plays something sloppy.
 */
function humanPolicy(board, tray, options, threshold, feverMult, rng) {
  if (rng() < 0.12) return options[Math.floor(rng() * options.length)];
  const sampleSize = Math.min(options.length, Math.max(8, Math.round(options.length * 0.3)));
  let best = null, bestVal = -Infinity;
  for (let k = 0; k < sampleSize; k++) {
    const o = options[Math.floor(rng() * options.length)];
    const copy = Int8Array.from(board);
    place(copy, tray[o.i], o.x, o.d);
    const res = resolve(copy, threshold, feverMult);
    let val = res.score + res.cleared * 10 - occupancy(copy) * 2;
    val += adjacencyBonus(copy, tray[o.i], o.x, o.d) * 0.5;
    val += (rng() - 0.5) * 40; // imprecision
    if (val > bestVal) { bestVal = val; best = o; }
  }
  return best;
}

function adjacencyBonus(board, piece, x, d) {
  let bonus = 0;
  for (const [r, c] of piece.cells) {
    const rr = r + d, cc = c + x;
    if (rr < 0 || rr >= CFG.rows) continue;
    if (board[idx(rr, cc)] !== piece.color) continue;
    const nb = [[rr - 1, cc], [rr + 1, cc], [rr, cc - 1], [rr, cc + 1]];
    for (const [nr, nc] of nb) {
      if (nr < 0 || nr >= CFG.rows || nc < 0 || nc >= CFG.cols) continue;
      if (board[idx(nr, nc)] === piece.color) bonus += 5;
    }
  }
  return bonus;
}

// ---------------------------------------------------------------- reporting

function pct(a, b) { return b === 0 ? 0 : Math.round((a / b) * 1000) / 10; }
function median(arr) {
  const s = [...arr].sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : 0;
}
function mean(arr) { return arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0; }

function report(name, runs) {
  const scores = runs.map((r) => r.score);
  const lens = runs.map((r) => r.placements);
  const chainTotals = {};
  let blastP = 0, allP = 0;
  for (const r of runs) {
    for (const k of Object.keys(r.chainHist)) chainTotals[k] = (chainTotals[k] || 0) + r.chainHist[k];
    blastP += r.blastPlacements; allP += r.placements;
  }
  const deep = runs.map((r) => {
    let n = 0;
    for (const k of Object.keys(r.chainHist)) if (+k >= 3) n += r.chainHist[k];
    return n;
  });
  console.log(`\n=== ${name} (${runs.length} runs) ===`);
  console.log(`score        median ${median(scores).toLocaleString()}  mean ${Math.round(mean(scores)).toLocaleString()}  max ${Math.max(...scores).toLocaleString()}`);
  console.log(`placements   median ${median(lens)}  mean ${Math.round(mean(lens))}  min ${Math.min(...lens)}  max ${Math.max(...lens)}`);
  console.log(`short runs   <20 placements: ${pct(lens.filter((l) => l < 20).length, lens.length)}%`);
  console.log(`blast rate   ${pct(blastP, allP)}% of placements detonate something`);
  console.log(`chains >=3   median per run ${median(deep)}  mean ${Math.round(mean(deep) * 10) / 10}`);
  console.log(`best chain   median ${median(runs.map((r) => r.bestChain))}  max ${Math.max(...runs.map((r) => r.bestChain))}`);
  console.log(`fever        mean entries/run ${Math.round(mean(runs.map((r) => r.feverEntries)) * 10) / 10}`);
  console.log(`best streak  median ${median(runs.map((r) => r.bestStreak))}`);
  const levels = {};
  for (const r of runs) levels[r.maxLevel] = (levels[r.maxLevel] || 0) + 1;
  console.log(`died in stage: ${Object.keys(levels).sort().map((k) => `${+k + 1}:${pct(levels[k], runs.length)}%`).join('  ')}`);
  console.log(`immortal     ${pct(runs.filter((r) => r.placements >= CFG.safetyCap).length, runs.length)}% hit the ${CFG.safetyCap}-placement cap`);
  const depths = Object.keys(chainTotals).map(Number).sort((a, b) => a - b);
  console.log(`chain depth distribution: ${depths.map((d) => `${d}:${chainTotals[d]}`).join('  ')}`);
}

function main() {
  const n = parseInt(process.argv[2] || '400', 10);
  CFG.safetyCap = 1200;
  const rnd = [], hum = [], grd = [];
  for (let i = 0; i < n; i++) rnd.push(playRun(1000 + i * 7919, randomPolicy));
  for (let i = 0; i < n; i++) hum.push(playRun(1000 + i * 7919, humanPolicy));
  for (let i = 0; i < Math.max(10, n >> 2); i++) grd.push(playRun(1000 + i * 7919, greedyPolicy));
  console.log(`config: ${CFG.cols}x${CFG.rows} board, chain threshold ${CFG.chainThreshold}`);
  console.log('stages: ' + CFG.stages.map((s, i) => `${i + 1}) turn>=${s.turn}: ${s.colors}c thr${s.threshold} pc${s.minPiece}-${s.maxPiece}`).join('  '));
  report('random player (floor)', rnd);
  report('human proxy (calibration target)', hum);
  report('expert proxy (1-ply full search)', grd);
}

if (require.main === module) main();

module.exports = {
  CFG, PIECES, playRun, findGroups, restingOffset, applyGravity, resolve,
  greedyPolicy, randomPolicy, humanPolicy, activePieces,
};
