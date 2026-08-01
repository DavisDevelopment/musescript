// repaintReceipt.js — shareable, independently-verifiable repaint audit receipts.
//
// Canonical home: muse-script/js-client/repaintReceipt.js — this app copy is byte-identical
// (same convention as runShare.js); mederos-web/src/lib/repaintReceipt.ts is the TypeScript
// port (keep all three in sync). A receipt carries the audited Pine source, the
// engine's repaint findings (musescript/pinescript/translit/RepaintAudit.hx shape:
// line + detail), a source fingerprint, and a timestamp. Encoded `rr1.` + base64url
// JSON — the web's /repaint-receipt?r=<token> route decodes it, renders the card,
// and re-runs the audit in the visitor's own browser. Framework-agnostic: no DOM,
// no Node specifics.

export const RECEIPT_VERSION = 1;
const PREFIX = "rr1."; // repaint receipt v1

export const RECEIPT_WEB_BASE = "https://mederos.app/repaint-receipt";

/** @typedef {{ line: number, detail: string }} RepaintReceiptFinding */
/** @typedef {{
 *   v: number, source: string, findings: RepaintReceiptFinding[],
 *   pineVersion: number, srcHash: string, at: number, engine?: string
 * }} RepaintReceipt */

/** @returns {"repaints"|"clean"} */
export function receiptVerdict(receipt) {
  return receipt.findings.length > 0 ? "repaints" : "clean";
}

/** Two independent FNV-1a 32-bit passes over the UTF-8 bytes, concatenated to 16 hex
 *  chars. Deterministic everywhere (no BigInt); a tamper tell — the web receipt page
 *  re-audits the full source anyway. Must match the web twin bit-for-bit. */
export function srcFingerprint(source) {
  const bytes = utf8Bytes(source);
  const a = fnv1a32(bytes, 0x811c9dc5);
  const b = fnv1a32(bytes, 0xcbf29ce4);
  return a.toString(16).padStart(8, "0") + b.toString(16).padStart(8, "0");
}

function fnv1a32(bytes, basis) {
  let h = basis >>> 0;
  for (let i = 0; i < bytes.length; i++) {
    h ^= bytes[i];
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** Build a receipt from a repaint audit result (findings may be empty = clean receipt). */
export function makeRepaintReceipt({ source, findings, pineVersion, engine, at }) {
  if (!source || typeof source !== "string") throw new Error("repaintReceipt: source required");
  if (!Array.isArray(findings)) {
    throw new Error("repaintReceipt: findings array required (may be empty for a clean receipt)");
  }
  return {
    v: RECEIPT_VERSION,
    source,
    findings: findings.map((f) => ({ line: f.line | 0, detail: String(f.detail) })),
    pineVersion: Number.isFinite(pineVersion) ? pineVersion : 0,
    srcHash: srcFingerprint(source),
    at: Number.isFinite(at) ? at : Date.now(),
    engine: engine ? String(engine) : undefined,
  };
}

export function encodeRepaintReceipt(receipt) {
  return PREFIX + b64urlEncode(JSON.stringify(receipt));
}

export function decodeRepaintReceipt(token) {
  if (typeof token !== "string" || !token.startsWith(PREFIX)) {
    throw new Error("repaintReceipt: not a repaint receipt token");
  }
  const obj = JSON.parse(b64urlDecode(token.slice(PREFIX.length)));
  if (
    !obj || obj.v !== RECEIPT_VERSION || typeof obj.source !== "string" || !obj.source ||
    !Array.isArray(obj.findings) || typeof obj.srcHash !== "string"
  ) {
    throw new Error("repaintReceipt: unrecognized receipt schema");
  }
  return /** @type {RepaintReceipt} */ (obj);
}

/** The web URL where anyone can open + independently re-verify this receipt. */
export function repaintReceiptUrl(receipt, base = RECEIPT_WEB_BASE) {
  return `${base}?r=${encodeRepaintReceipt(receipt)}`;
}

/**
 * Coerce pasted input into a receipt. Accepts, in order:
 *  - an `rr1.` token (or any URL containing `?r=rr1...`, e.g. a /repaint-receipt link)
 *  - receipt JSON (the full receipt object)
 *  - a raw audit-result JSON: `{ source, findings|repaint, pineVersion|version }`
 *    (the engine's RepaintAudit finding shape: [{ line, detail }])
 */
export function coerceRepaintReceipt(text) {
  const t = String(text ?? "").trim();
  if (!t) throw new Error("repaintReceipt: nothing to read");

  const tokenMatch = t.match(/rr1\.[A-Za-z0-9_-]+/);
  if (tokenMatch) return decodeRepaintReceipt(tokenMatch[0]);

  let obj;
  try {
    obj = JSON.parse(t);
  } catch {
    throw new Error("repaintReceipt: expected an rr1. token, a receipt link, or audit JSON");
  }
  if (obj && obj.v === RECEIPT_VERSION && typeof obj.srcHash === "string") {
    return decodeRepaintReceipt(PREFIX + b64urlEncode(JSON.stringify(obj)));
  }
  const findings = Array.isArray(obj?.findings) ? obj.findings
    : Array.isArray(obj?.repaint) ? obj.repaint : null;
  if (!obj || typeof obj.source !== "string" || !findings) {
    throw new Error("repaintReceipt: audit JSON needs { source, findings|repaint }");
  }
  return makeRepaintReceipt({
    source: obj.source,
    findings,
    pineVersion: obj.pineVersion ?? obj.version,
    engine: obj.engine,
    at: obj.at,
  });
}

// ── portable base64url (browser btoa / Node Buffer), UTF-8 safe — same as runShare.js ─────────
function b64urlEncode(str) {
  const bytes = utf8Bytes(str);
  let b64;
  if (typeof globalThis.btoa === "function") {
    let bin = "";
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    b64 = globalThis.btoa(bin);
  } else {
    b64 = Buffer.from(bytes).toString("base64");
  }
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(token) {
  const b64 = token.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((token.length + 3) % 4);
  let bytes;
  if (typeof globalThis.atob === "function") {
    const bin = globalThis.atob(b64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } else {
    bytes = new Uint8Array(Buffer.from(b64, "base64"));
  }
  return utf8Decode(bytes);
}

function utf8Bytes(str) {
  if (typeof TextEncoder !== "undefined") return new TextEncoder().encode(str);
  return new Uint8Array(Buffer.from(str, "utf-8"));
}
function utf8Decode(bytes) {
  if (typeof TextDecoder !== "undefined") return new TextDecoder().decode(bytes);
  return Buffer.from(bytes).toString("utf-8");
}
