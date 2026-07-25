#!/usr/bin/env node
/*
 * Config sweep for Chroma Cascade. The calibration target is the *human* proxy:
 *   - median run 60..120 placements
 *   - 30..50% of placements detonate something
 *   - a few chains of depth >= 3 per run
 * The greedy proxy stands in for an expert and is allowed to last much longer.
 */
'use strict';

const sim = require('./simulate.js');
const { CFG } = sim;

const BASE = JSON.parse(JSON.stringify(CFG));

function setCfg(o) {
  Object.assign(CFG, JSON.parse(JSON.stringify(BASE)));
  for (const k of Object.keys(o)) {
    if (k === 'colors') {
      CFG.stages = [
        { score: 0, colors: o.colors },
        { score: 3000, colors: o.colors + 1 },
        { score: 12000, colors: o.colors + 1 },
        { score: 30000, colors: Math.min(6, o.colors + 2) },
      ];
    } else CFG[k] = o[k];
  }
}

function stats(runs) {
  const lens = runs.map((r) => r.placements).sort((a, b) => a - b);
  const q = (p) => lens[Math.min(lens.length - 1, Math.floor(lens.length * p))];
  let blastP = 0, allP = 0, deep = 0, immortal = 0;
  for (const r of runs) {
    blastP += r.blastPlacements; allP += r.placements;
    for (const k of Object.keys(r.chainHist)) if (+k >= 3) deep += r.chainHist[k];
    if (r.placements >= CFG.safetyCap) immortal++;
  }
  const scores = runs.map((r) => r.score).sort((a, b) => a - b);
  return {
    medLen: q(0.5), p10: q(0.1), p90: q(0.9),
    blast: Math.round((blastP / allP) * 100),
    deepPerRun: Math.round((deep / runs.length) * 10) / 10,
    medScore: scores[Math.floor(scores.length / 2)],
    immortal: Math.round((immortal / runs.length) * 100),
    fever: Math.round((runs.reduce((a, r) => a + r.feverEntries, 0) / runs.length) * 10) / 10,
  };
}

const RUNS = parseInt(process.argv[2] || '40', 10);

const grid = [];
for (const rows of [8, 9, 10]) {
  for (const colors of [4, 5]) {
    for (const baseThreshold of [6]) {
      for (const chainThreshold of [3, 4]) {
        for (const [minPieceSize, maxPieceSize] of [[1, 4], [2, 5]]) {
          grid.push({ rows, colors, baseThreshold, chainThreshold, minPieceSize, maxPieceSize });
        }
      }
    }
  }
}

console.log('rows col thr/ch piece | HUMAN: medLen p10 p90 blast% ch3+ fever medScore imm% | EXPERT: medLen blast% imm% medScore');
console.log('-'.repeat(128));
for (const g of grid) {
  setCfg(Object.assign({
    mode: 'free', cols: 8, safetyCap: 400,
    feverThreshold: g.baseThreshold - 1,
  }, g));
  const hu = [], gr = [];
  for (let i = 0; i < RUNS; i++) hu.push(sim.playRun(1000 + i * 7919, sim.humanPolicy));
  for (let i = 0; i < Math.max(8, RUNS >> 1); i++) gr.push(sim.playRun(1000 + i * 7919, sim.greedyPolicy));
  const a = stats(hu), b = stats(gr);
  console.log(
    `${String(g.rows).padStart(4)} ${String(g.colors).padStart(3)} ${(g.baseThreshold + '/' + g.chainThreshold).padStart(6)} ${(g.minPieceSize + '-' + g.maxPieceSize).padStart(5)} |` +
    ` ${String(a.medLen).padStart(9)} ${String(a.p10).padStart(3)} ${String(a.p90).padStart(3)} ${String(a.blast).padStart(6)} ${String(a.deepPerRun).padStart(4)} ${String(a.fever).padStart(5)} ${String(a.medScore).padStart(8)} ${String(a.immortal).padStart(4)} |` +
    ` ${String(b.medLen).padStart(10)} ${String(b.blast).padStart(6)} ${String(b.immortal).padStart(4)} ${String(b.medScore).padStart(8)}`
  );
}
