#!/usr/bin/env node
/*
 * Config sweep for Chroma Cascade.
 *
 * The calibration target is the *human* proxy:
 *   - median run 100..150 placements (a run should end while it is still fun)
 *   - 30..45% of placements detonate something
 *   - a handful of really big single-colour blasts per run, not dozens
 *   - 0% of runs fail to terminate, for every policy
 */
'use strict';

const sim = require('./simulate.js');
const { CFG } = sim;

const BASE = JSON.parse(JSON.stringify(CFG));

const TABLES = {
  // threshold ramps to 10; difficulty comes from the requirement itself
  steep: [
    { turn: 0, colors: 4, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 15, colors: 5, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 35, colors: 5, threshold: 6, minPiece: 1, maxPiece: 5 },
    { turn: 60, colors: 6, threshold: 6, minPiece: 2, maxPiece: 5 },
    { turn: 85, colors: 6, threshold: 7, minPiece: 2, maxPiece: 5 },
    { turn: 115, colors: 6, threshold: 8, minPiece: 3, maxPiece: 5 },
    { turn: 150, colors: 6, threshold: 9, minPiece: 3, maxPiece: 5 },
    { turn: 200, colors: 6, threshold: 10, minPiece: 4, maxPiece: 5 },
  ],
  // same ceiling, reached much sooner
  fast: [
    { turn: 0, colors: 4, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 10, colors: 5, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 24, colors: 5, threshold: 6, minPiece: 1, maxPiece: 5 },
    { turn: 40, colors: 6, threshold: 7, minPiece: 2, maxPiece: 5 },
    { turn: 60, colors: 6, threshold: 8, minPiece: 2, maxPiece: 5 },
    { turn: 85, colors: 6, threshold: 9, minPiece: 3, maxPiece: 5 },
    { turn: 115, colors: 6, threshold: 10, minPiece: 3, maxPiece: 5 },
    { turn: 150, colors: 6, threshold: 11, minPiece: 4, maxPiece: 5 },
  ],
  // colours climb early, requirement stays humane — pressure from clutter
  clutter: [
    { turn: 0, colors: 4, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 10, colors: 5, threshold: 5, minPiece: 1, maxPiece: 4 },
    { turn: 22, colors: 6, threshold: 6, minPiece: 1, maxPiece: 5 },
    { turn: 40, colors: 6, threshold: 7, minPiece: 2, maxPiece: 5 },
    { turn: 62, colors: 6, threshold: 8, minPiece: 2, maxPiece: 5 },
    { turn: 88, colors: 6, threshold: 9, minPiece: 3, maxPiece: 5 },
    { turn: 118, colors: 6, threshold: 10, minPiece: 3, maxPiece: 5 },
    { turn: 152, colors: 6, threshold: 11, minPiece: 4, maxPiece: 5 },
  ],
};

function setCfg(o) {
  Object.assign(CFG, JSON.parse(JSON.stringify(BASE)));
  for (const k of Object.keys(o)) {
    if (k === 'table') CFG.stages = JSON.parse(JSON.stringify(TABLES[o.table]));
    else CFG[k] = o[k];
  }
}

function stats(runs) {
  const lens = runs.map((r) => r.placements).sort((a, b) => a - b);
  const q = (p) => lens[Math.min(lens.length - 1, Math.floor(lens.length * p))];
  let blastP = 0, allP = 0, immortal = 0;
  for (const r of runs) {
    blastP += r.blastPlacements; allP += r.placements;
    if (r.placements >= CFG.safetyCap) immortal++;
  }
  const scores = runs.map((r) => r.score).sort((a, b) => a - b);
  const mean = (f) => Math.round((runs.reduce((a, r) => a + f(r), 0) / runs.length) * 10) / 10;
  const big = [...runs.map((r) => r.biggestGroup)].sort((a, b) => a - b);
  return {
    medLen: q(0.5), p10: q(0.1), p90: q(0.9),
    blast: Math.round((blastP / allP) * 100),
    medScore: scores[Math.floor(scores.length / 2)],
    immortal: Math.round((immortal / runs.length) * 100),
    fever: mean((r) => r.feverEntries),
    biggest: big[Math.floor(big.length / 2)],
    big10: mean((r) => r.bigBlasts),
    big15: mean((r) => r.hugeBlasts),
  };
}

const RUNS = parseInt(process.argv[2] || '40', 10);

const grid = [];
for (const table of ['steep', 'fast', 'clutter']) {
  for (const chainRelief of [1, 2]) {
    grid.push({ table, chainRelief });
  }
}

console.log('table    relief | HUMAN medLen  p10  p90 blast% fever big10 big15 maxGrp imm% | EXPERT medLen imm%');
console.log('-'.repeat(118));
for (const g of grid) {
  setCfg(Object.assign({ mode: 'free', cols: 8, rows: 10, safetyCap: 600, monoColorChain: true }, g));
  const hu = [], gr = [];
  for (let i = 0; i < RUNS; i++) hu.push(sim.playRun(1000 + i * 7919, sim.humanPolicy));
  for (let i = 0; i < Math.max(8, RUNS >> 1); i++) gr.push(sim.playRun(1000 + i * 7919, sim.greedyPolicy));
  const a = stats(hu), b = stats(gr);
  console.log(
    `${g.table.padEnd(8)} ${String(g.chainRelief).padStart(6)} |` +
    ` ${String(a.medLen).padStart(11)} ${String(a.p10).padStart(4)} ${String(a.p90).padStart(4)}` +
    ` ${String(a.blast).padStart(6)} ${String(a.fever).padStart(5)} ${String(a.big10).padStart(5)}` +
    ` ${String(a.big15).padStart(5)} ${String(a.biggest).padStart(6)} ${String(a.immortal).padStart(4)} |` +
    ` ${String(b.medLen).padStart(13)} ${String(b.immortal).padStart(4)}`
  );
}
