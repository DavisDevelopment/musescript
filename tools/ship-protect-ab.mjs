#!/usr/bin/env node
/**
 * ship-protect-ab.mjs — Medium vs Heavy A/B on critical MuseRuntime paths.
 *
 * Pass rule (plan): prefer Heavy if MuseRuntime.run AND distill/rank-style
 * overhead are both ≤15% over Medium; else lock Medium.
 *
 * Writes:
 *   build/ship/LOCKED_PRESET
 *   build/ship/ab-report.json
 *
 * Usage:
 *   node tools/ship-protect-ab.mjs
 *   (requires build/ship/{medium,heavy}/muse-runtime.js from ship-js.mjs)
 */
import { createRequire } from "node:module";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const SHIP = join(ROOT, "build", "ship");
const HEAVY_BUDGET = 0.15;

const STRATEGY = `param fast: Scalar = 8
param slow: Scalar = 26
strategy AbProtect {
  onBar {
    f = sma(close, fast)
    s = sma(close, slow)
    when crossover(f, s): { long() }
    when crossunder(f, s): { flat() }
  }
}`;

function walkTape(n, seed) {
  let s = seed >>> 0;
  const rnd = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const gauss = () => {
    let u = 0;
    let v = 0;
    while (u === 0) u = rnd();
    while (v === 0) v = rnd();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  };
  const bars = [];
  let px = 100;
  for (let i = 0; i < n; i++) {
    px = Math.max(1, px * (1 + gauss() * 0.012));
    const open = px * (1 + gauss() * 0.002);
    const close = px * (1 + gauss() * 0.002);
    bars.push({
      open,
      high: Math.max(open, close) * 1.003,
      low: Math.min(open, close) * 0.997,
      close,
      volume: 1000 + rnd() * 400,
      time: i,
    });
  }
  return bars;
}

/** Load Haxe IIFE in an isolated context; return MuseRuntime global. */
function loadMuseRuntime(jsPath) {
  const code = readFileSync(jsPath, "utf8");
  const sandbox = {
    console,
    Math,
    Date,
    Array,
    Object,
    String,
    Number,
    Boolean,
    JSON,
    Error,
    TypeError,
    RegExp,
    Map,
    Set,
    WeakMap,
    WeakSet,
    Promise,
    Uint8Array,
    Float64Array,
    Int32Array,
    ArrayBuffer,
    parseInt,
    parseFloat,
    isNaN,
    isFinite,
    undefined,
  };
  sandbox.globalThis = sandbox;
  sandbox.self = sandbox;
  sandbox.window = sandbox;
  sandbox.exports = {};
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: jsPath, timeout: 120000 });
  const rt =
    sandbox.MuseRuntime ||
    sandbox.exports?.MuseRuntime ||
    sandbox.globalThis?.MuseRuntime;
  if (!rt || typeof rt.run !== "function") {
    throw new Error(`MuseRuntime not found after loading ${jsPath}`);
  }
  return rt;
}

function benchRun(rt, bars, iters) {
  // Warm
  const warm = rt.run(STRATEGY, bars, { tier: "js", seed: 42, skipTruthReport: true });
  if (!warm || warm.ok === false) {
    throw new Error(`MuseRuntime.run failed: ${warm?.error || "unknown"}`);
  }
  const t0 = performance.now();
  for (let i = 0; i < iters; i++) {
    rt.run(STRATEGY, bars, { tier: "js", seed: 42, skipTruthReport: true });
  }
  const t1 = performance.now();
  return { ms: t1 - t0, perIter: (t1 - t0) / iters, sharpe: warm.sharpe, trades: warm.trades };
}

function benchParseEval(jsPath, iters) {
  const code = readFileSync(jsPath, "utf8");
  // Cold-ish: new context each iter would dominate; measure compile+run once cold + reuse parse cost via Script
  const coldSandbox = { console, Math, Date, Array, Object, String, Number, Boolean, JSON, Error, undefined };
  coldSandbox.globalThis = coldSandbox;
  coldSandbox.self = coldSandbox;
  coldSandbox.window = coldSandbox;
  coldSandbox.exports = {};
  vm.createContext(coldSandbox);
  const tCold0 = performance.now();
  vm.runInContext(code, coldSandbox, { filename: jsPath, timeout: 120000 });
  const tCold1 = performance.now();

  const script = new vm.Script(code, { filename: jsPath });
  const t0 = performance.now();
  for (let i = 0; i < iters; i++) {
    const sb = {
      console,
      Math,
      Date,
      Array,
      Object,
      String,
      Number,
      Boolean,
      JSON,
      Error,
      undefined,
    };
    sb.globalThis = sb;
    sb.self = sb;
    sb.window = sb;
    sb.exports = {};
    vm.createContext(sb);
    script.runInContext(sb, { timeout: 120000 });
  }
  const t1 = performance.now();
  return {
    coldMs: tCold1 - tCold0,
    warmMs: t1 - t0,
    warmPerIter: (t1 - t0) / iters,
    bytes: Buffer.byteLength(code, "utf8"),
  };
}

/** Lightweight rank-from-features style CPU stand-in (no mobile import graph). */
function benchRankHotPath(iters) {
  // Synthetic feature scoring mirroring rankFromFeatures shape (dot + nonlinear gates).
  const feats = Float64Array.from({ length: 64 }, (_, i) => Math.sin(i * 0.17));
  const weights = Float64Array.from({ length: 64 }, (_, i) => Math.cos(i * 0.11));
  const t0 = performance.now();
  let acc = 0;
  for (let n = 0; n < iters; n++) {
    let s = 0;
    for (let i = 0; i < 64; i++) s += feats[i] * weights[i];
    acc += Math.tanh(s) * (1 / (1 + Math.exp(-s)));
  }
  const t1 = performance.now();
  return { ms: t1 - t0, perIter: (t1 - t0) / iters, acc };
}

async function main() {
  const mediumPath = join(SHIP, "medium", "muse-runtime.js");
  const heavyPath = join(SHIP, "heavy", "muse-runtime.js");
  if (!existsSync(mediumPath) || !existsSync(heavyPath)) {
    console.error("Missing ship artifacts. Run: node tools/ship-js.mjs");
    process.exit(1);
  }

  const bars = walkTape(500, 7);
  const runIters = 8;
  const parseIters = 3;

  console.log("[ab] loading medium…");
  const rtMed = loadMuseRuntime(mediumPath);
  console.log("[ab] loading heavy…");
  const rtHvy = loadMuseRuntime(heavyPath);

  console.log("[ab] MuseRuntime.run medium…");
  const runMed = benchRun(rtMed, bars, runIters);
  console.log("[ab] MuseRuntime.run heavy…");
  const runHvy = benchRun(rtHvy, bars, runIters);

  console.log("[ab] parse/eval…");
  const parseMed = benchParseEval(mediumPath, parseIters);
  const parseHvy = benchParseEval(heavyPath, parseIters);

  // Rank hot path is app-side (not engine-obfuscated here); still reported as baseline CPU.
  const rank = benchRankHotPath(50000);

  const runOverhead = (runHvy.perIter - runMed.perIter) / runMed.perIter;
  const parseOverhead = (parseHvy.warmPerIter - parseMed.warmPerIter) / parseMed.warmPerIter;

  // Critical systems (1) MuseRuntime.run (2) Lab/rank stand-in — for engine A/B,
  // (2) is parse/eval load cost as the engine-side proxy; rank is informational.
  const heavyClears =
    runOverhead <= HEAVY_BUDGET && parseOverhead <= HEAVY_BUDGET;

  const locked = heavyClears ? "heavy" : "medium";

  const report = {
    generatedAt: new Date().toISOString(),
    budget: HEAVY_BUDGET,
    locked,
    heavyClears,
    museRuntimeRun: {
      mediumPerIterMs: runMed.perIter,
      heavyPerIterMs: runHvy.perIter,
      overhead: runOverhead,
      mediumSharpe: runMed.sharpe,
      heavySharpe: runHvy.sharpe,
    },
    hubParseEval: {
      mediumColdMs: parseMed.coldMs,
      heavyColdMs: parseHvy.coldMs,
      mediumWarmPerIterMs: parseMed.warmPerIter,
      heavyWarmPerIterMs: parseHvy.warmPerIter,
      overhead: parseOverhead,
      mediumBytes: parseMed.bytes,
      heavyBytes: parseHvy.bytes,
    },
    rankHotPathBaseline: rank,
  };

  mkdirSync(SHIP, { recursive: true });
  writeFileSync(join(SHIP, "ab-report.json"), JSON.stringify(report, null, 2), "utf8");
  writeFileSync(join(SHIP, "LOCKED_PRESET"), locked + "\n", "utf8");

  // Mirror lock into mobile for Vite ship mode / CI.
  const mobileLock = resolve(ROOT, "..", "..", "mobile", "scripts", "ship-protect.lock.json");
  try {
    writeFileSync(
      mobileLock,
      JSON.stringify(
        {
          preset: locked,
          generatedAt: report.generatedAt,
          budget: HEAVY_BUDGET,
          heavyClears,
          source: "muse-lab/muse-script/build/ship/ab-report.json",
        },
        null,
        2,
      ) + "\n",
      "utf8",
    );
    console.log(`Mirrored lock → ${mobileLock}`);
  } catch (e) {
    console.warn(`Could not mirror lock to mobile: ${e.message}`);
  }

  console.log(JSON.stringify(report, null, 2));
  console.log(`\nLOCKED_PRESET=${locked} (heavy clears budget: ${heavyClears})`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
