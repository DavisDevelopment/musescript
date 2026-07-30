// runShare.js — shareable, independently-verifiable backtest receipts (the "Reproduce this run" core).
//
// The growth loop: a user shares a link; a stranger opens it; their OWN browser re-runs the strategy
// on the same seed via the same byte-identical muse-runtime, recomputes the equity digest, and gets a
// green "✓ reproduced bit-for-bit" + the honest verdict — nothing uploaded, nothing trusted, verified
// locally. This module is framework-agnostic (no DOM, no Node specifics): web + app both import it from
// the shared js-client contract; the runtime + tape loader are injected.
//
// Contract with the runtime (museRuntimeApi): runStrategy(source, bars, { seed, nTrials }) resolves to
// a result carrying `equityDigest` (EquityDigest.of — raw-bit SHA1 prefix) and, when available,
// `truthReport.verdict`. Reproduction = re-run + compare digests; a match is bit-identity to the
// strength of the digest.

export const SHARE_VERSION = 1;
const PREFIX = "mr1."; // muse-run v1

/** @typedef {{
 *   v: number, source: string, seed: number, nTrials: number,
 *   tapeId: string, barsDigest?: string, equityDigest: string,
 *   verdict?: string, engine?: string
 * }} RunShare */

/** Build a share payload from a completed run. `equityDigest` is what actually gets verified. */
export function makeRunShare({ source, seed, nTrials, tapeId, barsDigest, equityDigest, verdict, engine }) {
  if (!source || typeof source !== "string") throw new Error("runShare: source required");
  if (!equityDigest) throw new Error("runShare: equityDigest required (nothing to verify against)");
  return {
    v: SHARE_VERSION,
    source,
    seed: Number.isFinite(seed) ? (seed | 0) : 42,
    nTrials: Number.isFinite(nTrials) && nTrials > 0 ? Math.floor(nTrials) : 1,
    tapeId: String(tapeId ?? ""),
    barsDigest: barsDigest ? String(barsDigest) : undefined,
    equityDigest: String(equityDigest),
    verdict: verdict ? String(verdict) : undefined,
    engine: engine ? String(engine) : undefined,
  };
}

/** Encode a share to a compact, URL-safe token. */
export function encodeRunShare(share) {
  return PREFIX + b64urlEncode(JSON.stringify(share));
}

/** Decode a token back to a share; throws on a malformed/foreign token. */
export function decodeRunShare(token) {
  if (typeof token !== "string" || !token.startsWith(PREFIX)) {
    throw new Error("runShare: not a muse-run share token");
  }
  const obj = JSON.parse(b64urlDecode(token.slice(PREFIX.length)));
  if (!obj || obj.v !== SHARE_VERSION || !obj.source || !obj.equityDigest) {
    throw new Error("runShare: unrecognized share schema");
  }
  return /** @type {RunShare} */ (obj);
}

/**
 * Reproduce a shared run locally and report whether it matched bit-for-bit.
 * @param {RunShare} share
 * @param {{
 *   loadBars: (tapeId: string) => Promise<any[]> | any[],
 *   runStrategy: (source: string, bars: any[], opts: { seed: number, nTrials: number }) => Promise<any>,
 *   barsDigest?: (bars: any[]) => string,   // optional — verify the tape matches before running
 * }} deps
 * @returns {Promise<{
 *   ok: boolean, matched: boolean, barsMatch: boolean|null,
 *   expected: string, got: string|null,
 *   verdictExpected?: string, verdictGot?: string, verdictMatch: boolean|null,
 *   reason?: string
 * }>}
 */
export async function reproduceRunShare(share, deps) {
  try {
    if (!deps || typeof deps.loadBars !== "function" || typeof deps.runStrategy !== "function") {
      return fail(share, "runShare: loadBars + runStrategy required");
    }
    const bars = await deps.loadBars(share.tapeId);
    if (!Array.isArray(bars) || bars.length === 0) {
      return fail(share, `runShare: tape "${share.tapeId}" unavailable — can't reproduce`);
    }

    // If both sides can digest the bars, confirm the INPUT matches before trusting the output.
    let barsMatch = null;
    if (share.barsDigest && typeof deps.barsDigest === "function") {
      barsMatch = deps.barsDigest(bars) === share.barsDigest;
      if (!barsMatch) {
        return { ...fail(share, "input tape differs — reproduction not comparable"), barsMatch: false };
      }
    }

    const result = await deps.runStrategy(share.source, bars, {
      seed: share.seed,
      nTrials: share.nTrials,
    });
    const got = result && result.equityDigest != null ? String(result.equityDigest) : null;
    const verdictGot = result && result.truthReport && result.truthReport.verdict
      ? String(result.truthReport.verdict) : undefined;

    const matched = got != null && got === share.equityDigest;
    return {
      ok: true,
      matched,
      barsMatch,
      expected: share.equityDigest,
      got,
      verdictExpected: share.verdict,
      verdictGot,
      verdictMatch: share.verdict != null && verdictGot != null ? verdictGot === share.verdict : null,
      reason: matched ? undefined : (got == null ? "run produced no equity digest" : "equity digest differs"),
    };
  } catch (e) {
    return fail(share, "runShare: reproduction error — " + (e && e.message ? e.message : String(e)));
  }
}

function fail(share, reason) {
  return {
    ok: false, matched: false, barsMatch: null,
    expected: share ? share.equityDigest : "", got: null,
    verdictExpected: share ? share.verdict : undefined, verdictGot: undefined, verdictMatch: null,
    reason,
  };
}

// ── portable base64url (browser btoa / Node Buffer), UTF-8 safe ──────────────────────────────
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
