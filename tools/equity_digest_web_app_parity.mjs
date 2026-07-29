#!/usr/bin/env node
/**
 * Web ↔ app EquityDigest parity gate (CURSOR_TODO Task 1 accept).
 *
 * Proves the same strategy + bars + seed yields identical equityDigest / fillDigest
 * / Truth Report verdict when run through the shared museRuntimeApi contract against
 * each host's vendored muse-runtime.js:
 *   - muse-script build/js/muse-runtime.js (canonical)
 *   - mederos-web/public/muse-runtime.js   (web /studio)
 *   - kalshai/mobile/src/lab/muse-runtime.js (app / Instrument Terminal)
 *
 * Run (from muse-script root):
 *   node tools/equity_digest_web_app_parity.mjs
 *   # or:
 *   bash tools/equity_digest_web_app_parity_ci.sh
 *   pwsh tools/equity_digest_web_app_parity_ci.ps1
 *
 * Env:
 *   MUSE_RUNTIME_BUILD / MUSE_RUNTIME_WEB / MUSE_RUNTIME_MOBILE — override paths
 *   MUSE_PARITY_STRICT=1 — fail if web or mobile runtime is missing (local accept)
 *   WRITE_GOLDEN=1 — rewrite testdata/equity-digest-web-app.golden.json
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { createMuseRuntimeApi } from "../js-client/museRuntimeApi.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const goldenPath = path.join(root, "testdata", "equity-digest-web-app.golden.json");

const BUY_HOLD = `
strategy BuyHold {
  onBar {
    when position() == 0: long()
  }
}
`;

const SEED = 42;
const N_BARS = 120;

function synthBars(n, seed) {
  const out = [];
  let price = 100.0;
  let s = seed;
  for (let i = 0; i < n; i++) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    const ret = ((s % 2001) - 1000) / 100000;
    const open = price;
    const close = price * (1 + ret);
    const high = Math.max(open, close) * 1.001;
    const low = Math.min(open, close) * 0.999;
    out.push({ open, high, low, close, volume: 1000 + (s % 500), time: i });
    price = close;
  }
  return out;
}

function defaultPaths() {
  return {
    build: process.env.MUSE_RUNTIME_BUILD || path.join(root, "build", "js", "muse-runtime.js"),
    web:
      process.env.MUSE_RUNTIME_WEB ||
      path.resolve(root, "..", "..", "..", "mederos-web", "public", "muse-runtime.js"),
    mobile:
      process.env.MUSE_RUNTIME_MOBILE ||
      path.resolve(root, "..", "..", "mobile", "src", "lab", "muse-runtime.js"),
  };
}

function sha256File(file) {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function loadMuseRuntime(runtimePath) {
  // Isolated VM load: muse-runtime.js is a Haxe IIFE that attaches to `exports`.
  // Avoid Node's createRequire — mobile's package.json has "type":"module", which
  // loads the IIFE as ESM (`this`/`exports` undefined) and crashes.
  const abs = path.resolve(runtimePath);
  const code = fs.readFileSync(abs, "utf8");
  const exports = {};
  const sandbox = {
    exports,
    module: { exports },
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
    RangeError,
    parseInt,
    parseFloat,
    isFinite,
    isNaN,
    Infinity,
    NaN,
    undefined,
    Int8Array,
    Uint8Array,
    Uint8ClampedArray,
    Int16Array,
    Uint16Array,
    Int32Array,
    Uint32Array,
    Float32Array,
    Float64Array,
    ArrayBuffer,
    DataView,
    Map,
    Set,
    WeakMap,
    WeakSet,
    Promise,
    Symbol,
    Reflect,
    Proxy,
    BigInt,
    performance: typeof performance !== "undefined" ? performance : { now: () => Date.now() },
  };
  sandbox.global = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.self = sandbox;
  sandbox.window = sandbox;
  vm.runInNewContext(code, sandbox, { filename: abs, timeout: 120_000 });
  const MuseRuntime = exports.MuseRuntime || sandbox.MuseRuntime;
  if (!MuseRuntime || typeof MuseRuntime.run !== "function") {
    throw new Error(`MuseRuntime.run missing after loading ${abs}`);
  }
  return MuseRuntime;
}

async function runHost(label, runtimePath, bars) {
  const MuseRuntime = loadMuseRuntime(runtimePath);
  const api = createMuseRuntimeApi(MuseRuntime);
  if (!api.runtimeReady()) throw new Error(`${label}: runtime not ready`);

  const result = await api.runStrategy(BUY_HOLD, bars, {
    tier: "js",
    initialCash: 100000,
    seed: SEED,
    honestOos: true,
    oosFrac: 0.25,
    embargoBars: 20,
  });
  if (!result || result.ok !== true) {
    throw new Error(`${label}: run failed — ${result?.error || "unknown"}`);
  }

  const proof = api.proveDeterminism(BUY_HOLD, bars, { seed: SEED, engines: ["interp", "js"] });
  const digestFromCurve = api.equityDigest(result.equity);

  return {
    label,
    path: runtimePath,
    fileSha256: sha256File(runtimePath),
    equityDigest: result.equityDigest ?? null,
    fillDigest: result.fillDigest ?? null,
    digestFromCurve: digestFromCurve ?? null,
    verdict: result.truthReport?.verdict ?? null,
    trades: result.trades ?? null,
    seed: result.repro?.seed ?? null,
    proofOk: !!proof?.ok,
    proofIdentical: !!proof?.identical,
    proofDigest: proof?.equityDigest ?? null,
    proofBadge: proof?.badge ?? null,
  };
}

function pick(obj, keys) {
  const out = {};
  for (const k of keys) out[k] = obj[k];
  return out;
}

function fail(msg) {
  console.error(`EQUITY_DIGEST_WEB_APP_PARITY FAIL: ${msg}`);
  process.exit(1);
}

const paths = defaultPaths();
const bars = synthBars(N_BARS, SEED);
const strict = process.env.MUSE_PARITY_STRICT === "1";

const present = {};
for (const [label, p] of Object.entries(paths)) {
  if (fs.existsSync(p)) present[label] = p;
  else console.warn(`  skip ${label}: missing ${p}`);
}

if (!present.build) {
  fail(`canonical build runtime missing: ${paths.build} (run: haxe build-runtime.hxml)`);
}

const hosts = [];
for (const [label, p] of Object.entries(present)) {
  process.stdout.write(`  run ${label}… `);
  const row = await runHost(label, p, bars);
  console.log(
    `equityDigest=${row.equityDigest} fillDigest=${row.fillDigest} verdict=${row.verdict}`,
  );
  hosts.push(row);
}

const build = hosts.find((h) => h.label === "build");
const web = hosts.find((h) => h.label === "web");
const mobile = hosts.find((h) => h.label === "mobile");

if (build.equityDigest !== build.digestFromCurve) {
  fail(`build equityDigest !== EquityDigest.of(equity): ${build.equityDigest} vs ${build.digestFromCurve}`);
}
if (build.seed !== SEED) fail(`build repro.seed=${build.seed}, expected ${SEED}`);
if (!build.proofOk || !build.proofIdentical) {
  fail(`build proveDeterminism not BIT_IDENTICAL (badge=${build.proofBadge})`);
}
if (build.proofDigest !== build.equityDigest) {
  fail(`build proof equityDigest drifted from run: ${build.proofDigest} vs ${build.equityDigest}`);
}

const compareKeys = ["equityDigest", "fillDigest", "verdict", "trades", "seed"];
for (const h of hosts) {
  if (h.label === "build") continue;
  for (const k of compareKeys) {
    if (h[k] !== build[k]) {
      fail(`${h.label}.${k}=${JSON.stringify(h[k])} !== build.${k}=${JSON.stringify(build[k])}`);
    }
  }
  if (h.fileSha256 !== build.fileSha256) {
    fail(`${h.label} muse-runtime.js SHA256 diverged from build (re-sync from haxe build-runtime.hxml)`);
  }
}

if (strict && (!web || !mobile)) {
  fail("MUSE_PARITY_STRICT=1 requires both web and mobile muse-runtime.js paths");
}

const snapshot = {
  schema: "mederos.equityDigest.webAppParity.v1",
  strategy: "BuyHold",
  seed: SEED,
  nBars: N_BARS,
  equityDigest: build.equityDigest,
  fillDigest: build.fillDigest,
  verdict: build.verdict,
  trades: build.trades,
  museRuntimeSha256: build.fileSha256,
  hosts: hosts.map((h) => pick(h, ["label", "equityDigest", "fillDigest", "verdict", "fileSha256"])),
};

if (process.env.WRITE_GOLDEN === "1") {
  fs.mkdirSync(path.dirname(goldenPath), { recursive: true });
  fs.writeFileSync(goldenPath, JSON.stringify(snapshot, null, 2) + "\n", "utf8");
  console.log(`wrote golden ${goldenPath}`);
}

if (!fs.existsSync(goldenPath)) {
  fail(`golden missing: ${goldenPath} (re-run with WRITE_GOLDEN=1 after intentional change)`);
}

const golden = JSON.parse(fs.readFileSync(goldenPath, "utf8"));
for (const k of ["equityDigest", "fillDigest", "verdict", "trades", "seed", "nBars"]) {
  if (snapshot[k] !== golden[k]) {
    fail(`golden drift on ${k}: got ${JSON.stringify(snapshot[k])} expected ${JSON.stringify(golden[k])}`);
  }
}
if (snapshot.museRuntimeSha256 !== golden.museRuntimeSha256) {
  // Soft: Haxe major/minor can rewrite the JS bundle without changing digests.
  console.warn(
    `warn: muse-runtime.js SHA256 != golden (ok if Haxe toolchain differs; digests still gated)\n` +
      `  got  ${snapshot.museRuntimeSha256}\n` +
      `  want ${golden.museRuntimeSha256}`,
  );
}

const cross =
  web && mobile
    ? "web == app == build == golden"
    : web || mobile
      ? `${web ? "web" : "mobile"} == build == golden (other host skipped)`
      : "build == golden (web/app paths absent — set MUSE_PARITY_STRICT=1 for full accept)";

console.log(`EQUITY_DIGEST_WEB_APP_PARITY_OK (${cross})`);
console.log(
  JSON.stringify(
    {
      equityDigest: build.equityDigest,
      fillDigest: build.fillDigest,
      verdict: build.verdict,
      hosts: hosts.map((h) => h.label),
    },
    null,
    2,
  ),
);
