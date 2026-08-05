/**
 * Sync parquet → columnar JSON for muse.pd.read_parquet (Node ingest).
 * Invoked via child_process.spawnSync from PdParquet — avoids Worker+Atomics races.
 *
 * Usage: node tools/parquet_read_sync.mjs <abs-path-to.parquet>
 * stdout: { ok: true, order: string[], columns: { [name]: (number|null)[] } }
 *      or { ok: false, error: string }
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
			if (typeof v === "bigint") v = Number(v);
			else if (typeof v === "boolean") v = v ? 1 : 0;
			else if (v == null || (typeof v === "number" && !Number.isFinite(v))) v = null;
			else if (typeof v !== "number") {
				const f = parseFloat(String(v));
				v = Number.isFinite(f) ? f : null;
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
