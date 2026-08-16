#!/usr/bin/env node
/**
 * OPEN_ITEMS 1.2 — grep ban on Array.shift() in musescript/indicators/lib/.
 *
 * Fail closed. `.unshift(` is allowed (pattern requires `.shift`).
 * Used as engine-matrix preflight and a cheap CI step (no Haxe).
 *
 *   node tools/ban_indicator_shift.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const LIB = path.join(ROOT, "musescript", "indicators", "lib");
const SHIFT_CALL = /\.shift\s*\(/;

function main() {
  if (!fs.existsSync(LIB) || !fs.statSync(LIB).isDirectory()) {
    console.error(`[shift-ban] missing ${LIB} (run from repo)`);
    process.exit(1);
  }
  const files = fs.readdirSync(LIB).filter((f) => f.endsWith(".hx")).sort();
  if (files.length < 100) {
    console.error(`[shift-ban] expected a populated indicators/lib/, found ${files.length} .hx`);
    process.exit(1);
  }
  const hits = [];
  for (const f of files) {
    const lines = fs.readFileSync(path.join(LIB, f), "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      if (SHIFT_CALL.test(lines[i])) hits.push(`${f}:${i + 1}`);
    }
  }
  if (hits.length) {
    console.error("[shift-ban] OPEN_ITEMS 1.2: `.shift()` is banned in musescript/indicators/lib/");
    console.error("  Use RingBuffer (O(1) eviction), not Array.shift() (O(n) compact).");
    for (const h of hits) console.error(`  ${h}`);
    process.exit(1);
  }
  console.log(`[shift-ban] OK  ${files.length} files in indicators/lib/ — zero .shift() calls`);
  process.exit(0);
}

main();
