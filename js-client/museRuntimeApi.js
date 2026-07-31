/**
 * Shared MuseRuntime API surface — web `/studio` + mobile Strategy Studio.
 *
 * Both hosts load the same Haxe→JS engine (`muse-runtime.js` from build-runtime.hxml).
 * Pass the loaded `MuseRuntime` global/module export into `createMuseRuntimeApi`.
 *
 * Mobile: `src/lab/museRuntimeClient.js` wraps this (ESM import of muse-runtime.js).
 * Web: `mederos-web/src/lib/museRuntimeClient.ts` wraps this (script-tag load).
 *
 * Parity accept (web ↔ app EquityDigest): `node tools/equity_digest_web_app_parity.mjs`
 * (or `tools/equity_digest_web_app_parity_ci.{sh,ps1}`; set `MUSE_PARITY_STRICT=1` when
 * mederos-web + mobile runtimes are on disk).
 */

/**
 * @param {object|null|undefined} MuseRuntime
 * @param {{ loadWabt?: () => Promise<any> }} [deps]
 */
export function createMuseRuntimeApi(MuseRuntime, deps = {}) {
  const loadWabt = deps.loadWabt || null;

  function runtimeReady() {
    return !!(MuseRuntime && typeof MuseRuntime.run === "function");
  }

  function notLoaded(extra = "") {
    return { ok: false, error: `muse runtime not loaded${extra ? ` — ${extra}` : ""}` };
  }

  async function runStrategy(source, bars, {
    tier = "js",
    initialCash = 100000,
    params = null,
    seed = 42,
    nTrials = null,
    honestOos = true,
    oosFrac = 0.25,
    embargoBars = 20,
    purgeEmbargoApplied = false,
    oosHeld = false,
    pbo = null,
    skipTruthReport = false,
  } = {}) {
    if (!runtimeReady()) return notLoaded();
    const opts = { instrument: true, initialCash, seed, honestOos, oosFrac, embargoBars };
    if (params) opts.params = params;
    if (nTrials != null) opts.nTrials = nTrials;
    if (purgeEmbargoApplied) opts.purgeEmbargoApplied = true;
    if (oosHeld) opts.oosHeld = true;
    if (pbo != null) opts.pbo = pbo;
    if (skipTruthReport) opts.skipTruthReport = true;

    if (tier === "wasm") {
      if (!loadWabt) return { ok: false, error: "wasm tier requires loadWabt" };
      const em = MuseRuntime.emitWat(source);
      if (!em || !em.ok) return { ok: false, error: (em && em.error) || "emitWat failed" };
      try {
        const wabt = await loadWabt();
        const mod = wabt.parseWat("strategy.wat", em.wat);
        const { buffer } = mod.toBinary({});
        mod.destroy();
        return MuseRuntime.runWasm(source, bars, buffer, opts);
      } catch (e) {
        return { ok: false, error: `wasm assemble: ${e?.message || e}` };
      }
    }

    return MuseRuntime.run(source, bars, { ...opts, tier });
  }

  function proveDeterminism(source, bars, opts = {}) {
    if (!runtimeReady() || typeof MuseRuntime.proveDeterminism !== "function") {
      return {
        ok: false,
        identical: false,
        badge: "ERROR",
        error: "muse runtime proveDeterminism API not loaded — rebuild muse-runtime.js",
        reason: "muse runtime proveDeterminism API not loaded — rebuild muse-runtime.js",
      };
    }
    return MuseRuntime.proveDeterminism(source, bars, { seed: 42, engines: ["interp", "js"], ...opts });
  }

  function evaluateTruthReport(payload) {
    if (!runtimeReady() || typeof MuseRuntime.evaluateTruthReport !== "function") {
      return { ok: false, error: "muse runtime truthReport API not loaded — rebuild muse-runtime.js" };
    }
    return MuseRuntime.evaluateTruthReport(payload);
  }

  function estimatePbo(perf, maxCombos = 2000) {
    if (!runtimeReady() || typeof MuseRuntime.estimatePbo !== "function") {
      return { ok: false, error: "muse runtime estimatePbo API not loaded — rebuild muse-runtime.js", pbo: null };
    }
    return MuseRuntime.estimatePbo(perf, maxCombos);
  }

  function syncTrialsCount(n) {
    if (!runtimeReady() || typeof MuseRuntime.trialsSetCount !== "function") return n;
    return MuseRuntime.trialsSetCount(n);
  }

  function checkStrategy(source, { strict = false } = {}) {
    if (!runtimeReady()) return notLoaded();
    return MuseRuntime.check(source, { strict });
  }

  function equityDigest(equity) {
    if (!runtimeReady() || typeof MuseRuntime.equityDigest !== "function") return null;
    return MuseRuntime.equityDigest(equity);
  }

  function evaluateLeaderboardEntry(entry, ctx = {}) {
    if (!runtimeReady() || typeof MuseRuntime.evaluateLeaderboardEntry !== "function") {
      return { ok: false, error: "muse runtime evaluateLeaderboardEntry API not loaded — rebuild muse-runtime.js" };
    }
    return MuseRuntime.evaluateLeaderboardEntry(entry, ctx);
  }

  function rankLeaderboard(entries, ctx = {}) {
    if (!runtimeReady() || typeof MuseRuntime.rankLeaderboard !== "function") {
      return { ok: false, error: "muse runtime rankLeaderboard API not loaded — rebuild muse-runtime.js" };
    }
    return MuseRuntime.rankLeaderboard(entries, ctx);
  }

  return {
    MuseRuntime,
    runtimeReady,
    runStrategy,
    proveDeterminism,
    evaluateTruthReport,
    estimatePbo,
    syncTrialsCount,
    checkStrategy,
    equityDigest,
    evaluateLeaderboardEntry,
    rankLeaderboard,
  };
}
