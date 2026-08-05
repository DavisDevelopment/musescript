/**
 * Sync parquet → columnar JSON for muse.pd.read_parquet (Node ingest).
 * Invoked via child_process.spawnSync from PdParquet — avoids Worker+Atomics races.
 *
 * Usage: node tools/parquet_read_sync.mjs <abs-path-to.parquet>
 * stdout: { ok: true, order: string[], columns: { [name]: (number|string|boolean|null)[] } }
 *      or { ok: false, error: string }
 *
 * Non-numeric strings are preserved for PdParquet.fromColumnar Str sidecars
 * (same policy as fromObjects / CSV). Bool → 0/1; non-finite numbers → null.
 */
import fs from "fs";

const absPath = process.argv[2];
if (!absPath) {
	process.stdout.write(JSON.stringify({ ok: false, error: "usage: parquet_read_sync.mjs <abs-path>" }));
	process.exit(0);
}

let parquetReadObjects;
try {
	({ parquetReadObjects } = await import("hyparquet"));
} catch (e) {
	process.stdout.write(JSON.stringify({
		ok: false,
		error: "optional peer hyparquet missing — npm i hyparquet (" + String(e && e.message ? e.message : e) + ")"
	}));
	process.exit(0);
}

try {
	const nodeBuf = fs.readFileSync(absPath);
	const file = nodeBuf.buffer.slice(nodeBuf.byteOffset, nodeBuf.byteOffset + nodeBuf.byteLength);
	const rows = await parquetReadObjects({ file });
	const order = [];
	const seen = Object.create(null);
	for (const row of rows) {
		if (!row) continue;
		for (const k of Object.keys(row)) {
			if (!seen[k]) {
				seen[k] = true;
				order.push(k);
			}
		}
	}
	const columns = {};
	for (const name of order) columns[name] = [];
	for (const row of rows) {
		for (const name of order) {
			let v = row == null ? null : row[name];
			if (typeof v === "bigint") {
				const n = Number(v);
				v = Number.isFinite(n) ? n : null;
			} else if (typeof v === "boolean") {
				v = v ? 1 : 0;
			} else if (v == null) {
				v = null;
			} else if (typeof v === "number") {
				v = Number.isFinite(v) ? v : null;
			} else if (typeof v === "string") {
				// Keep as string — fromColumnar classifies Str vs F64 (numeric-looking → F64).
			} else if (typeof v === "object" && v !== null && typeof v.toISOString === "function") {
				v = v.toISOString();
			} else {
				v = String(v);
			}
			columns[name].push(v);
		}
	}
	process.stdout.write(JSON.stringify({ ok: true, order, columns }));
} catch (e) {
	process.stdout.write(JSON.stringify({
		ok: false,
		error: String(e && e.message ? e.message : e)
	}));
}
