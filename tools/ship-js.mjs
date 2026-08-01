#!/usr/bin/env node
/**
 * ship-js.mjs — minify + obfuscate MuseScript Haxe→JS engines for ship channels.
 *
 * Inputs (raw golden — parity digests use these, never ship output):
 *   build/js/muse-runtime.js
 *   build/js/pine2muse-web.js
 *
 * Outputs:
 *   build/ship/{medium,heavy}/{muse-runtime,pine2muse-web}.js
 *   build/ship/manifest.json
 *   build/ship/LOCKED_PRESET  (written by ship-protect-ab.mjs; read if present for --locked)
 *
 * Usage:
 *   node tools/ship-js.mjs              # both presets
 *   node tools/ship-js.mjs --preset medium
 *   node tools/ship-js.mjs --locked     # only the locked preset (default medium if missing)
 */
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";
import JavaScriptObfuscator from "javascript-obfuscator";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const SHIP = join(ROOT, "build", "ship");

const INPUTS = [
  { name: "muse-runtime.js", keepNames: ["MuseRuntime", "MuseDebugSession"] },
  { name: "pine2muse-web.js", keepNames: ["PineConvert"] },
];

/** Medium: rename + string array + compact. No control-flow / self-defending. */
export const PRESET_MEDIUM = {
  compact: true,
  controlFlowFlattening: false,
  deadCodeInjection: false,
  debugProtection: false,
  debugProtectionInterval: 0,
  disableConsoleOutput: false,
  identifierNamesGenerator: "hexadecimal",
  renameGlobals: false,
  selfDefending: false,
  stringArray: true,
  stringArrayEncoding: ["base64"],
  stringArrayThreshold: 0.75,
  transformObjectKeys: true,
  unicodeEscapeSequence: false,
};

/** Heavy: Medium + control-flow + dead code + self-defending. */
export const PRESET_HEAVY = {
  ...PRESET_MEDIUM,
  controlFlowFlattening: true,
  controlFlowFlatteningThreshold: 0.75,
  deadCodeInjection: true,
  deadCodeInjectionThreshold: 0.4,
  selfDefending: true,
};

const PRESETS = {
  medium: PRESET_MEDIUM,
  heavy: PRESET_HEAVY,
};

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

function parseArgs(argv) {
  const out = { presets: ["medium", "heavy"], locked: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--preset" && argv[i + 1]) {
      out.presets = [argv[++i]];
    } else if (a === "--locked") {
      out.locked = true;
    } else if (a === "--help" || a === "-h") {
      out.help = true;
    }
  }
  return out;
}

function readLockedPreset() {
  const p = join(SHIP, "LOCKED_PRESET");
  if (!existsSync(p)) return "medium";
  const v = readFileSync(p, "utf8").trim().toLowerCase();
  return PRESETS[v] ? v : "medium";
}

async function minifySource(code, keepNames) {
  const result = await esbuild.transform(code, {
    minify: true,
    target: "es2018",
    legalComments: "none",
    // Keep exported facade names readable for global attach / loaders.
    keepNames: false,
    // Haxe IIFE is plain JS; treat as script.
    loader: "js",
  });
  // esbuild keepNames is for functions; additionally ensure string literals for
  // global export names survive obfuscator via reservedNames below.
  void keepNames;
  return result.code;
}

function obfuscate(code, presetName, reservedNames) {
  const opts = {
    ...PRESETS[presetName],
    reservedNames: reservedNames.map((n) => `^${n}$`),
    reservedStrings: reservedNames,
  };
  return JavaScriptObfuscator.obfuscate(code, opts).getObfuscatedCode();
}

export async function shipOne(inputPath, keepNames, presetName) {
  const raw = readFileSync(inputPath, "utf8");
  const minified = await minifySource(raw, keepNames);
  const shipped = obfuscate(minified, presetName, keepNames);
  return {
    rawBytes: Buffer.byteLength(raw, "utf8"),
    minBytes: Buffer.byteLength(minified, "utf8"),
    shipBytes: Buffer.byteLength(shipped, "utf8"),
    rawHash: sha256(raw),
    shipHash: sha256(shipped),
    code: shipped,
    minified,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(`Usage: node tools/ship-js.mjs [--preset medium|heavy] [--locked]`);
    process.exit(0);
  }

  let presets = args.presets;
  if (args.locked) {
    presets = [readLockedPreset()];
    console.log(`Using locked preset: ${presets[0]}`);
  }

  for (const p of presets) {
    if (!PRESETS[p]) {
      console.error(`Unknown preset: ${p}`);
      process.exit(1);
    }
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    presets: {},
  };

  for (const presetName of presets) {
    const outDir = join(SHIP, presetName);
    mkdirSync(outDir, { recursive: true });
    const entry = { files: {} };

    for (const inp of INPUTS) {
      const src = join(ROOT, "build", "js", inp.name);
      if (!existsSync(src)) {
        console.error(`Missing input: ${src} — run haxe build-runtime.hxml / build-pine-web.hxml first`);
        process.exit(1);
      }
      console.log(`[ship] ${inp.name} → ${presetName}…`);
      const r = await shipOne(src, inp.keepNames, presetName);
      const dest = join(outDir, inp.name);
      writeFileSync(dest, r.code, "utf8");
      // Also keep minify-only sibling for A/B baseline.
      writeFileSync(join(outDir, inp.name.replace(/\.js$/, ".min.js")), r.minified, "utf8");
      entry.files[inp.name] = {
        rawBytes: r.rawBytes,
        minBytes: r.minBytes,
        shipBytes: r.shipBytes,
        rawHash: r.rawHash,
        shipHash: r.shipHash,
        path: `build/ship/${presetName}/${inp.name}`,
      };
      console.log(
        `  raw ${(r.rawBytes / 1024).toFixed(0)}KB → min ${(r.minBytes / 1024).toFixed(0)}KB → ship ${(r.shipBytes / 1024).toFixed(0)}KB`,
      );
    }
    manifest.presets[presetName] = entry;
  }

  mkdirSync(SHIP, { recursive: true });
  writeFileSync(join(SHIP, "manifest.json"), JSON.stringify(manifest, null, 2), "utf8");
  console.log(`Wrote ${join(SHIP, "manifest.json")}`);
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
