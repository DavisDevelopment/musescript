// repaintReceipt.selftest.mjs — node selftest for the shareable repaint-receipt core.
// Run: node js-client/repaintReceipt.selftest.mjs
// Twin of kalshai/mobile/src/lab/repaintReceipt.selftest.js against the canonical module here.

import {
  RECEIPT_VERSION,
  makeRepaintReceipt,
  encodeRepaintReceipt,
  decodeRepaintReceipt,
  coerceRepaintReceipt,
  receiptVerdict,
  srcFingerprint,
  repaintReceiptUrl,
} from "./repaintReceipt.js";

let pass = 0;
let fail = 0;

function check(name, cond) {
  if (cond) {
    pass++;
    console.log(`  ok   - ${name}`);
  } else {
    fail++;
    console.log(`  FAIL - ${name}`);
  }
}

const PINE = `//@version=5
indicator("HTF Trend", overlay=true)
htf = request.security(syminfo.tickerid, "D", close, lookahead=barmerge.lookahead_on)
plot(htf)`;

const FINDINGS = [
  { line: 3, detail: "request.security(lookahead=barmerge.lookahead_on) peeks at future data" },
];

console.log("1. make → encode → decode round-trips");
{
  const r = makeRepaintReceipt({ source: PINE, findings: FINDINGS, pineVersion: 5, engine: "pine2muse@test" });
  const back = decodeRepaintReceipt(encodeRepaintReceipt(r));
  check("version stamped", back.v === RECEIPT_VERSION);
  check("source survives", back.source === PINE);
  check("findings survive", back.findings.length === 1 && back.findings[0].line === 3);
  check("engine survives", back.engine === "pine2muse@test");
  check("timestamp is finite", Number.isFinite(back.at));
}

console.log("2. verdict + fingerprint semantics");
{
  const dirty = makeRepaintReceipt({ source: PINE, findings: FINDINGS });
  const clean = makeRepaintReceipt({ source: PINE, findings: [] });
  check("findings → repaints", receiptVerdict(dirty) === "repaints");
  check("no findings → clean", receiptVerdict(clean) === "clean");
  check("fingerprint is 16 hex chars", /^[0-9a-f]{16}$/.test(dirty.srcHash));
  check("fingerprint is deterministic", srcFingerprint(PINE) === dirty.srcHash);
  check("fingerprint tracks the source", srcFingerprint(PINE + " ") !== dirty.srcHash);
}

console.log("3. coerce accepts token / link / receipt JSON / raw audit JSON");
{
  const r = makeRepaintReceipt({ source: PINE, findings: FINDINGS, pineVersion: 5 });
  const token = encodeRepaintReceipt(r);
  check("bare token", coerceRepaintReceipt(token).srcHash === r.srcHash);
  check("web link", coerceRepaintReceipt(repaintReceiptUrl(r)).srcHash === r.srcHash);
  check("receipt JSON", coerceRepaintReceipt(JSON.stringify(r)).srcHash === r.srcHash);
  const audit = { source: PINE, repaint: FINDINGS, version: 5 };
  const fromAudit = coerceRepaintReceipt(JSON.stringify(audit));
  check("raw audit JSON (converter shape)", fromAudit.findings.length === 1 && fromAudit.pineVersion === 5);
}

console.log("4. malformed input throws (never a silent bad receipt)");
{
  const throws = (fn) => { try { fn(); return false; } catch { return true; } };
  check("empty input", throws(() => coerceRepaintReceipt("")));
  check("foreign token", throws(() => decodeRepaintReceipt("mr1.abcd")));
  check("non-JSON garbage", throws(() => coerceRepaintReceipt("not a receipt")));
  check("JSON without source", throws(() => coerceRepaintReceipt(JSON.stringify({ repaint: [] }))));
  check("missing findings in make", throws(() => makeRepaintReceipt({ source: PINE })));
}

console.log("5. web URL shape matches /repaint-receipt?r=rr1.…");
{
  const r = makeRepaintReceipt({ source: PINE, findings: FINDINGS });
  const url = repaintReceiptUrl(r);
  check("url targets the receipt route", url.startsWith("https://mederos.app/repaint-receipt?r=rr1."));
  check("token is URL-safe", !/[+/=]/.test(url.split("?r=")[1]));
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
