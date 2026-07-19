#!/usr/bin/env node
// run_universe_scan.js — Run a universe-scan .ms strategy over a bySym JSON panel
// (as built by tools/fund_panel_loader.py or the equities_daily.db exporter used
// for examples/universe-scan/README.md) via MuseRuntime.runPanel, honest fills.
//
// Usage:
//   node tools/run_universe_scan.js <strategy.ms> <bySym.json> [--costBps 10] [--noFillNextOpen]
//
// Always benchmarks with fillNextOpen:true + costBps (default 10) unless overridden —
// see examples/universe-scan/README.md for why (same-bar lookahead / frictionless
// fantasy both measurably inflate results on this codebase).
const fs = require("fs");
const path = require("path");

require(path.join(__dirname, "..", "build", "js", "muse-runtime.js"));

function main() {
  const args = process.argv.slice(2);
  const pos = args.filter((a) => !a.startsWith("--"));
  if (pos.length < 2) {
    console.error("usage: run_universe_scan.js <strategy.ms> <bySym.json> [--costBps N] [--noFillNextOpen] [--initialCash N]");
    process.exit(1);
  }
  const [strategyPath, panelPath] = pos;
  const flag = (name, def) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 ? args[i + 1] : def;
  };
  const costBps = parseFloat(flag("costBps", "10"));
  const fillNextOpen = !args.includes("--noFillNextOpen");
  const initialCash = parseFloat(flag("initialCash", "100000"));

  const source = fs.readFileSync(strategyPath, "utf8");
  const bySym = JSON.parse(fs.readFileSync(panelPath, "utf8"));
  const nSym = Object.keys(bySym).length;
  const nBars = nSym > 0 ? bySym[Object.keys(bySym)[0]].length : 0;
  console.log(`strategy=${strategyPath} panel=${panelPath} symbols=${nSym} bars~${nBars} `
    + `fillNextOpen=${fillNextOpen} costBps=${costBps}`);

  const t0 = Date.now();
  const result = MuseRuntime.runPanel(source, bySym, {
    tier: "js",
    fillNextOpen,
    costBps,
    initialCash,
    instrument: false,
  });
  const elapsed = (Date.now() - t0) / 1000;

  if (!result.ok) {
    console.error("FAILED:", result.error);
    process.exit(1);
  }
  console.log(JSON.stringify({
    backend: result.backend,
    bars: result.bars,
    symbols: result.symbols ? result.symbols.length : 0,
    trades: result.trades,
    sharpe: result.sharpe,
    maxDrawdown: result.maxDrawdown,
    winRate: result.winRate,
    finalEquity: result.finalEquity,
    elapsedSec: elapsed,
  }, null, 2));
}

main();
