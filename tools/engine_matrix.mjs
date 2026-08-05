#!/usr/bin/env node
/**
 * Engine-matrix honesty gate — build + run each critical suite.
 * Fail closed on any non-zero haxe/node exit. Prints suite names.
 *
 * Usage:
 *   node tools/engine_matrix.mjs
 *   node tools/engine_matrix.mjs --list
 *   node tools/engine_matrix.mjs --only ndarray,pd
 *   node tools/engine_matrix.mjs --soak          # optional prefer-vm-soak only
 *   node tools/engine_matrix.mjs --with-optional # default suites + optional
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const MANIFEST = path.join(__dirname, "engine_matrix_suites.json");
const SHELL = process.platform === "win32";

function run(cmd, args, label) {
  const r = spawnSync(cmd, args, {
    cwd: ROOT,
    stdio: "inherit",
    shell: SHELL,
    env: process.env,
  });
  if (r.error) {
    console.error(`[engine-matrix] ${label}: failed to spawn ${cmd}: ${r.error.message}`);
    return 1;
  }
  return r.status == null ? 1 : r.status;
}

function loadManifest() {
  const raw = fs.readFileSync(MANIFEST, "utf8");
  return JSON.parse(raw);
}

function parseOnly(argv) {
  const i = argv.indexOf("--only");
  if (i < 0 || !argv[i + 1]) return null;
  return new Set(
    argv[i + 1]
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
  );
}

function catalog(manifest) {
  const optional = manifest.optional ?? [];
  return [...manifest.suites, ...optional];
}

function main() {
  const argv = process.argv.slice(2);
  const manifest = loadManifest();
  const optional = manifest.optional ?? [];
  const all = catalog(manifest);

  if (argv.includes("--list") || argv.includes("-l")) {
    console.log("Engine-matrix suites (default):");
    for (const s of manifest.suites) {
      console.log(`  - ${s.name}  (${s.hxml} → ${s.js})`);
      if (s.covers?.length) console.log(`      covers: ${s.covers.join("; ")}`);
    }
    if (optional.length) {
      console.log("Optional / soak (not in default matrix):");
      for (const s of optional) {
        console.log(`  - ${s.name}  (${s.hxml} → ${s.js})`);
        if (s.covers?.length) console.log(`      covers: ${s.covers.join("; ")}`);
        if (s.note) console.log(`      note: ${s.note}`);
      }
    }
    if (manifest.alternate) {
      console.log(`  (alternate, not default) ${manifest.alternate.name}: ${manifest.alternate.note}`);
    }
    process.exit(0);
  }

  const soakOnly = argv.includes("--soak");
  const withOptional = argv.includes("--with-optional");
  const only = parseOnly(argv);

  let suites;
  if (soakOnly) {
    suites = optional.filter((s) => s.name === "prefer-vm-soak" || (s.name && s.name.includes("soak")));
    if (!suites.length) suites = optional;
  } else if (only) {
    suites = all.filter((s) => only.has(s.name));
  } else if (withOptional) {
    suites = all;
  } else {
    suites = manifest.suites;
  }

  if (only) {
    const missing = [...only].filter((n) => !all.some((s) => s.name === n));
    if (missing.length) {
      console.error(`[engine-matrix] unknown suite(s): ${missing.join(", ")}`);
      console.error(`Known: ${all.map((s) => s.name).join(", ")}`);
      process.exit(1);
    }
  }
  if (!suites.length) {
    console.error("[engine-matrix] no suites selected");
    process.exit(1);
  }

  const names = suites.map((s) => s.name);
  console.log("══════════════════════════════════════════════════════");
  console.log(" Muse engine-matrix honesty gate");
  console.log(` Suites (${suites.length}): ${names.join(", ")}`);
  console.log("══════════════════════════════════════════════════════");

  const results = [];
  for (const s of suites) {
    console.log("");
    console.log(`──────── ${s.name} ────────`);
    console.log(`haxe ${s.hxml}`);
    const buildCode = run("haxe", [s.hxml], `build:${s.name}`);
    if (buildCode !== 0) {
      console.error(`[engine-matrix] FAIL suite=${s.name} phase=build exit=${buildCode}`);
      results.push({ name: s.name, ok: false, phase: "build", code: buildCode });
      continue;
    }
    console.log(`node ${s.js}`);
    const runCode = run("node", [s.js], `run:${s.name}`);
    if (runCode !== 0) {
      console.error(`[engine-matrix] FAIL suite=${s.name} phase=run exit=${runCode}`);
      results.push({ name: s.name, ok: false, phase: "run", code: runCode });
      continue;
    }
    console.log(`[engine-matrix] OK   suite=${s.name}`);
    results.push({ name: s.name, ok: true });
  }

  const failed = results.filter((r) => !r.ok);
  console.log("");
  console.log("══════════════════════════════════════════════════════");
  console.log(" Summary");
  for (const r of results) {
    if (r.ok) console.log(`  PASS  ${r.name}`);
    else console.log(`  FAIL  ${r.name}  (${r.phase} exit ${r.code})`);
  }
  if (failed.length) {
    console.error(
      `[engine-matrix] ${failed.length}/${results.length} suite(s) failed: ${failed.map((f) => f.name).join(", ")}`
    );
    process.exit(1);
  }
  console.log(`[engine-matrix] all ${results.length} suite(s) passed`);
  process.exit(0);
}

main();
