// runShare.selftest.mjs — node selftest for the shareable/verifiable run-receipt core.
// Run: node js-client/runShare.selftest.mjs

import {
  makeRunShare, encodeRunShare, decodeRunShare, reproduceRunShare, SHARE_VERSION,
} from "./runShare.js";

let failed = 0;
function ok(cond, msg) { if (cond) { console.log("ok: " + msg); } else { failed++; console.error("FAIL: " + msg); } }

// A deterministic mock runtime: equity/verdict are a pure function of (source, seed) — mirrors the
// byte-identical real runtime (same input → same digest), so we can test the reproduce logic offline.
function mockDigest(source, seed) {
  let h = 0x811c9dc5;
  const s = `${source}|${seed}`;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return (h >>> 0).toString(16).padStart(8, "0") + "0000000000000000".slice(0, 8);
}
const mockRuntime = {
  loadBars: (tapeId) => (tapeId === "MISSING" ? [] : [{ close: 100 }, { close: 101 }, { close: 102 }]),
  runStrategy: (source, _bars, { seed }) => ({
    equityDigest: mockDigest(source, seed),
    truthReport: { verdict: source.includes("robust") ? "Robust" : "Coin-flip" },
  }),
  barsDigest: (bars) => "bd" + bars.length,
};

const SRC = "strategy robust { onBar { when position()==0: long() } }";
const share = makeRunShare({
  source: SRC, seed: 42, nTrials: 5, tapeId: "SPY_DAILY",
  barsDigest: "bd3", equityDigest: mockDigest(SRC, 42), verdict: "Robust", engine: "muse-1",
});

// ── encode / decode round-trip ──────────────────────────────────────────────
const token = encodeRunShare(share);
ok(typeof token === "string" && token.startsWith("mr1."), "token has versioned prefix");
const back = decodeRunShare(token);
ok(back.v === SHARE_VERSION && back.source === SRC && back.equityDigest === share.equityDigest, "round-trips");
ok(back.seed === 42 && back.nTrials === 5, "seed + trials preserved (DSR bar reproduces)");

let threw = false;
try { decodeRunShare("not-a-token"); } catch { threw = true; }
ok(threw, "foreign token rejected");
try { threw = false; decodeRunShare("mr1." + Buffer.from('{"v":1}').toString("base64url")); } catch { threw = true; }
ok(threw, "schema-incomplete token rejected");

// ── reproduce: exact match ──────────────────────────────────────────────────
const r = await reproduceRunShare(share, mockRuntime);
ok(r.ok && r.matched, "identical re-run → matched bit-for-bit");
ok(r.expected === r.got, "expected === got digest");
ok(r.barsMatch === true, "input tape digest confirmed before trusting output");
ok(r.verdictMatch === true, "verdict reproduced");

// ── reproduce: drift is caught ──────────────────────────────────────────────
const drifted = { ...share, equityDigest: "deadbeefdeadbeef" };
const r2 = await reproduceRunShare(drifted, mockRuntime);
ok(r2.ok && !r2.matched && r2.reason === "equity digest differs", "any drift → not matched, honest reason");

// ── reproduce: wrong tape ───────────────────────────────────────────────────
const r3 = await reproduceRunShare({ ...share, barsDigest: "bd999" }, mockRuntime);
ok(!r3.matched && r3.barsMatch === false, "different input tape → flagged, not silently 'reproduced'");

// ── reproduce: tape unavailable ─────────────────────────────────────────────
const r4 = await reproduceRunShare({ ...share, tapeId: "MISSING" }, mockRuntime);
ok(!r4.ok && /unavailable/.test(r4.reason), "missing tape → honest failure, never a fake green");

console.log(failed === 0 ? "\nrunShare selftest: all passed" : `\nrunShare selftest: ${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
