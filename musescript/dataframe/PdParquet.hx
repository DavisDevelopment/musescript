package musescript.dataframe;

import musescript.io.FsGrant;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.ndarray.NdArrayF64;

/**
 * Grant-gated Parquet → DataFrame (ingest tier).
 *
 * Node: optional peer `hyparquet` (pure JS, 0 transitive deps) via
 * `tools/parquet_read_sync.mjs` + spawnSync (ESM-safe).
 * JVM / non-Node: clear {@link IoDenied} — use Node ingest or preconvert to CSV.
 * Fitness / null grants → {@link IoDenied} (same as {@link PdCsv}).
 *
 * `fromObjects`: numeric / bool → F64; non-numeric strings → Str sidecar
 * (empty/NA tokens → `""`). `fromColumnar` / Node helper path stays F64-only
 * (string parquet columns still coerce to NaN — use CSV or post-`assignStr`).
 */
class PdParquet {
	public static function readParquet(?grants:Null<IoGrant>, path:String):DataFrame {
		ensureFsHost("pd_read_parquet");
		var r = FsGrant.resolve("pd_read_parquet", grants, path, false);
		#if (sys || nodejs)
		if (!sys.FileSystem.exists(r.nativeAbs) || sys.FileSystem.isDirectory(r.nativeAbs))
			throw new IoDenied("pd_read_parquet", 'not a file: ${r.museAbs}');
		#if (js && nodejs)
		return decodeNodeFile(r.nativeAbs);
		#else
		throw new IoDenied("pd_read_parquet",
			"parquet decode unavailable on this host (Node + optional hyparquet peer; or preconvert to CSV)");
		#end
		#else
		throw new IoDenied("pd_read_parquet", "filesystem unavailable on this host");
		#end
	}

	/** Build frame from row objects (no IO) — used by tests / host bridges. */
	public static function fromObjects(rows:Array<Dynamic>):DataFrame {
		if (rows == null || rows.length == 0) return DataFrame.empty();
		var order:Array<String> = [];
		var seen = new Map<String, Bool>();
		for (row in rows) {
			if (row == null) continue;
			for (k in Reflect.fields(row)) {
				if (!seen.exists(k)) {
					seen.set(k, true);
					order.push(k);
				}
			}
		}
		if (order.length == 0) return DataFrame.empty();
		var n = rows.length;
		var isStr:Array<Bool> = [for (_ in 0...order.length) false];
		for (c in 0...order.length) {
			var name = order[c];
			for (ri in 0...n) {
				var row = rows[ri];
				var v:Dynamic = row == null ? null : Reflect.field(row, name);
				if (cellLooksStr(v)) {
					isStr[c] = true;
					break;
				}
			}
		}
		var map = new Map<String, NdArrayF64>();
		var fOrder:Array<String> = [];
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (c in 0...order.length) {
			var name = order[c];
			if (isStr[c]) {
				var labels:Array<String> = [];
				for (ri in 0...n) {
					var row = rows[ri];
					var v:Dynamic = row == null ? null : Reflect.field(row, name);
					labels.push(cellToStr(v));
				}
				sOrder.push(name);
				sMap.set(name, labels);
			} else {
				var col = NdArrayF64.empty([n]);
				for (ri in 0...n) {
					var row = rows[ri];
					var v:Dynamic = row == null ? null : Reflect.field(row, name);
					col.setFlat(ri, cellToFloat(v));
				}
				fOrder.push(name);
				map.set(name, col);
			}
		}
		return DataFrame.fromColumns(map, Index.range(n), fOrder, sMap, sOrder);
	}

	/** True when a cell forces the whole column into Str sidecar. */
	static function cellLooksStr(v:Dynamic):Bool {
		if (v == null) return false;
		if (Std.isOfType(v, Bool)) return false;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return false;
		#if js
		if (js.Syntax.typeof(v) == "bigint") return false;
		#end
		if (Std.isOfType(v, String)) {
			var s = StringTools.trim(Std.string(v));
			if (s.length == 0 || s == "nan" || s == "NaN" || s == "NA" || s == "null" || s == "None")
				return false;
			var f = Std.parseFloat(s);
			if (Math.isNaN(f)) return true;
			// Numeric-looking string stays F64 (same policy as CSV).
			return !PdCsv.floatStringLooksComplete(s);
		}
		return true;
	}

	static function cellToStr(v:Dynamic):String {
		if (v == null) return "";
		if (Std.isOfType(v, String)) {
			var s = StringTools.trim(Std.string(v));
			if (s.length == 0 || s == "nan" || s == "NaN" || s == "NA" || s == "null" || s == "None")
				return "";
			return s;
		}
		return Std.string(v);
	}

	/** Columnar payload from Node bridge: `{ order: string[], columns: { name: number[] } }`. */
	public static function fromColumnar(payload:Dynamic):DataFrame {
		if (payload == null) return DataFrame.empty();
		var orderDyn:Dynamic = Reflect.field(payload, "order");
		var colsDyn:Dynamic = Reflect.field(payload, "columns");
		if (colsDyn == null) return DataFrame.empty();
		var order:Array<String> = [];
		if (Std.isOfType(orderDyn, Array)) {
			var arr:Array<Dynamic> = cast orderDyn;
			for (x in arr) order.push(Std.string(x));
		} else {
			for (k in Reflect.fields(colsDyn)) order.push(k);
		}
		if (order.length == 0) return DataFrame.empty();
		var n = 0;
		var first = Reflect.field(colsDyn, order[0]);
		if (Std.isOfType(first, Array)) n = (cast first : Array<Dynamic>).length;
		var map = new Map<String, NdArrayF64>();
		for (name in order) {
			var raw:Dynamic = Reflect.field(colsDyn, name);
			var col = NdArrayF64.empty([n]);
			if (Std.isOfType(raw, Array)) {
				var arr:Array<Dynamic> = cast raw;
				for (i in 0...n) col.setFlat(i, cellToFloat(i < arr.length ? arr[i] : null));
			} else {
				for (i in 0...n) col.setFlat(i, Math.NaN);
			}
			map.set(name, col);
		}
		return DataFrame.fromColumns(map, Index.range(n), order);
	}

	static function cellToFloat(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Bool)) return (v : Bool) ? 1.0 : 0.0;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
			var f:Float = cast v;
			return Math.isNaN(f) ? Math.NaN : f;
		}
		#if js
		// BigInt from hyparquet INT64 — coerce via Number / string.
		if (js.Syntax.typeof(v) == "bigint") {
			var n:Float = js.Syntax.code("Number({0})", v);
			return Math.isFinite(n) ? n : Math.NaN;
		}
		#end
		if (Std.isOfType(v, String)) {
			var s = StringTools.trim(Std.string(v));
			if (s.length == 0 || s == "nan" || s == "NaN" || s == "NA" || s == "null")
				return Math.NaN;
			var f = Std.parseFloat(s);
			return Math.isNaN(f) ? Math.NaN : f;
		}
		return Math.NaN;
	}

	#if (js && nodejs)
	static function decodeNodeFile(nativeAbs:String):DataFrame {
		try {
			var result:Dynamic = untyped js.Syntax.code("
				(function(absPath) {
					var cp = require('child_process');
					var pathMod = require('path');
					var fs = require('fs');
					var candidates = [
						pathMod.join(process.cwd(), 'tools', 'parquet_read_sync.mjs'),
						pathMod.resolve(__dirname, '..', '..', 'tools', 'parquet_read_sync.mjs'),
						pathMod.resolve(__dirname, '..', 'tools', 'parquet_read_sync.mjs')
					];
					var helper = null;
					for (var i = 0; i < candidates.length; i++) {
						if (fs.existsSync(candidates[i])) { helper = candidates[i]; break; }
					}
					if (!helper)
						return JSON.stringify({ ok: false, error: 'tools/parquet_read_sync.mjs not found (run from repo root)' });
					var r = cp.spawnSync(process.execPath, [helper, absPath], {
						encoding: 'utf8',
						maxBuffer: 64 * 1024 * 1024,
						windowsHide: true
					});
					if (r.error)
						return JSON.stringify({ ok: false, error: String(r.error.message || r.error) });
					var out = (r.stdout || '').toString().trim();
					if (!out)
						return JSON.stringify({
							ok: false,
							error: 'parquet helper empty stdout' + (r.stderr ? (': ' + String(r.stderr).slice(0, 400)) : '')
						});
					return out;
				})({0})
			", nativeAbs);
			var parsed:Dynamic = haxe.Json.parse(Std.string(result));
			if (parsed.ok != true)
				throw new IoDenied("pd_read_parquet", Std.string(Reflect.field(parsed, "error")));
			return fromColumnar(parsed);
		} catch (e:IoDenied) {
			throw e;
		} catch (e:Dynamic) {
			throw new IoDenied("pd_read_parquet", "parquet decode failed: " + Std.string(e));
		}
	}
	#end

	static function ensureFsHost(op:String):Void {
		#if !(sys || nodejs)
		throw new IoDenied(op, "filesystem unavailable on this host");
		#end
	}
}
