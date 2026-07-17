#!/usr/bin/env node
/**
 * Smoke test for the client-side MuseRuntime execution engine (Strategy Studio).
 * Proves the in-browser module runs backtests in-process and that all three
 * execution tiers agree: interp === js === wasm (bare-metal).
 *
 * Prereqs: `haxe build-runtime.hxml` (→ build/js/muse-runtime.js). The WASM tier
 * here assembles the emitted WAT with the Python wat2wasm tool as a stand-in for
 * the app's wabt.js; the browser app assembles WAT via wabt.js instead.
 *
 *   node tools/runtime_smoke.js
 */
const fs = require("fs");
const cp = require("child_process");
const path = require("path");

const M = require("../build/js/muse-runtime.js");
const R = M.MuseRuntime;

const SRC = `{
  @strategy("smoke")
  @on(bar) {
    if (crossover(sma("close", 5), sma("close", 20))) long();
    if (crossunder(sma("close", 5), sma("close", 20))) flat();
  }
}`;

// Deterministic bars matching BarFeed.synthetic's formula (seed 7).
function synthBars(n, seed) {
  const bars = [];
  let price = 100, rng = seed;
  for (let i = 0; i < n; i++) {
    rng = (rng * 1103515245 + 12345) & 0x7fffffff;
    const noise = ((rng % 1000) / 1000 - 0.5) * 2;
    const o = price, c = price * (1 + noise * 0.01);
    bars.push({ open: o, high: Math.max(o, c) * 1.002, low: Math.min(o, c) * 0.998,
                close: c, volume: 1000 + (rng % 500), time: i * 60 });
    price = c;
  }
  return bars;
}

function assert(cond, msg) { if (!cond) { console.error("FAIL:", msg); process.exit(1); } }

const bars = synthBars(300, 7);

// interp + js tiers (no external assembler)
const it = R.run(SRC, bars, { tier: "interp", instrument: true });
const js = R.run(SRC, bars, { tier: "js", instrument: true });
assert(it.ok && js.ok, "interp/js run ok");
assert(it.equity.length === 300 && it.fills.length > 0, "instrumentation populated");

// wasm tier: emit WAT → assemble (Python stands in for wabt.js) → runWasm
const em = R.emitWat(SRC);
assert(em.ok, "emitWat ok: " + (em.error || ""));
const dir = path.join(__dirname, "..", "build", "wasm");
fs.mkdirSync(dir, { recursive: true });
const watPath = path.join(dir, "smoke.wat"), wasmPath = path.join(dir, "smoke.wasm");
fs.writeFileSync(watPath, em.wat);
let py = path.join(__dirname, "..", ".venv", "Scripts", "python.exe");
if (!fs.existsSync(py)) py = path.join(__dirname, "..", ".venv", "bin", "python");
const asm = cp.spawnSync(py, [path.join(__dirname, "wat2wasm_cli.py"), watPath, wasmPath], { encoding: "utf8" });
assert(asm.status === 0, "wat2wasm: " + (asm.stderr || ""));
const bytes = new Uint8Array(fs.readFileSync(wasmPath));
const wa = R.runWasm(SRC, bars, bytes, { instrument: true });
assert(wa.ok, "runWasm ok: " + (wa.error || ""));

const agree =
  it.trades === js.trades && js.trades === wa.trades &&
  Math.abs((it.sharpe || 0) - (js.sharpe || 0)) < 1e-9 &&
  Math.abs((js.sharpe || 0) - (wa.sharpe || 0)) < 1e-9;
assert(agree, `three-way parity: interp=${it.trades}/${it.sharpe} js=${js.trades}/${js.sharpe} wasm=${wa.trades}/${wa.sharpe}`);

console.log(`OK  interp === js === wasm  (trades=${it.trades}, sharpe=${(it.sharpe || 0).toFixed(6)}, equity=${it.equity.length})`);

// --- debugger (MuseDebugSession): step / inspect / watch / breakpoint / parity ---
const DBG_SRC = `{
  @strategy("dbg")
  @on(bar) {
    fast = sma("close", 5);
    slow = sma("close", 20);
    if (crossover(fast, slow)) long();
    if (crossunder(fast, slow)) flat();
  }
}`;
const dfull = R.run(DBG_SRC, bars, { tier: "interp", instrument: true });

// stepped state at bar 50 must equal the full run's equity there
const d1 = R.debug(DBG_SRC, bars);
d1.runToBar(50);
const ins = d1.inspect();
assert(ins.index === 50, "runToBar lands on 50");
assert(Math.abs(ins.equity - dfull.equity[50]) < 1e-9, "paused equity@50 == full run");
// watch expression evaluates against live paused state
const w2 = d1.evalWatch('sma("close", 5) - sma("close", 20)');
assert(w2.ok && Math.abs(w2.value - (ins.vars.fast - ins.vars.slow)) < 1e-9, "watch eval matches inspected vars");
// guards report both conditions with a boolean truth
const g = d1.guards();
assert(g.length === 2 && typeof g[0].truth === "boolean", "guards list conditions with truth");

// breakpoint stops exactly at the requested bar
const d2 = R.debug(DBG_SRC, bars);
d2.setBreakpoint(100);
d2.continueRun();
assert(d2.inspect().index === 100, "breakpoint stops at bar 100");

// step-run to end === full run
const d3 = R.debug(DBG_SRC, bars);
d3.runToBar(9999);
const dres = d3.result();
assert(dres.trades === dfull.trades &&
  Math.abs((dres.sharpe || 0) - (dfull.sharpe || 0)) < 1e-9 &&
  dres.equity.length === dfull.equity.length, "step-run to end === full run");

console.log(`OK  debugger  (step/inspect/watch/breakpoint OK, step-run === full run: trades=${dres.trades})`);
