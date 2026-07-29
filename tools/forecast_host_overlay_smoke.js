#!/usr/bin/env node
// Smoke: ForecastHostRuntime auction bins + lattice ensemble (Initiative 2.2–2.4 API).
const path = require("path");
const RT = require(path.join(__dirname, "..", "build", "js", "forecast-host-runtime.js")).ForecastHostRuntime;
if (!RT || typeof RT.forecast !== "function") {
  console.error("ForecastHostRuntime not exposed");
  process.exit(1);
}

const bars = [];
let px = 100;
for (let i = 0; i < 60; i++) {
  px += (i % 7 === 0 ? 1.2 : i % 5 === 0 ? -0.8 : 0.15);
  bars.push({
    open: px, high: px + 0.4, low: px - 0.4, close: px,
    volume: 800 + i * 10, time: i,
  });
}

const auction = RT.forecast("auction", bars, { window: 20, bins: 24, includeBins: true });
if (!auction.ok) { console.error("auction fail", auction.error); process.exit(1); }
if (!Array.isArray(auction.state?.bins) || auction.state.bins.length !== 24) {
  console.error("expected 24 hist bins", auction.state);
  process.exit(1);
}
if (!(auction.state.bins[0].price > 0) || !(auction.state.bins[0].vol >= 0)) {
  console.error("bad bin shape", auction.state.bins[0]);
  process.exit(1);
}

const impulse = [];
const anchors = [0, 10, 20, 30, 40, 50];
const pxs = [100, 110, 105, 120, 112, 125];
let li = 0;
for (let i = 0; i < 51; i++) {
  while (li + 1 < anchors.length && anchors[li + 1] <= i) li++;
  const a = anchors[li], b = anchors[Math.min(li + 1, anchors.length - 1)];
  const pa = pxs[li], pb = pxs[Math.min(li + 1, pxs.length - 1)];
  const t = b > a ? (i - a) / (b - a) : 0;
  const p = pa + (pb - pa) * t;
  impulse.push({ open: p, high: p * 1.001, low: p * 0.999, close: p, volume: 1000, time: i });
}

const lattice = RT.forecast("lattice", impulse, { k: 5, includeEnsemble: true, includeCounts: true });
if (!lattice.ok) { console.error("lattice fail", lattice.error); process.exit(1); }
if (!Array.isArray(lattice.ensembles) || !lattice.ensembles[0]?.bands) {
  console.error("missing ensembles", lattice);
  process.exit(1);
}
console.log("ok auction.bins=", auction.state.bins.length,
  "lattice.ensembles.bands=", lattice.ensembles[0].bands.length,
  "counts=", lattice.counts?.[0]?.masses?.length);
