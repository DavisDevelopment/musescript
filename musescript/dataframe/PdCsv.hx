package musescript.dataframe;

import musescript.io.FsGrant;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.ndarray.NdArrayF64;

/**
 * Grant-gated CSV → DataFrame (M1 ingest tier).
 *
 * Columns that are entirely numeric (empty / NA tokens allowed) → F64.
 * Any column with a non-numeric non-empty cell → Str sidecar (labels as-is;
 * empty / NA tokens → `""`). Header required. Fitness / null grants →
 * {@link IoDenied}.
 */
class PdCsv {
	public static function readCsv(?grants:Null<IoGrant>, path:String):DataFrame {
		ensureFsHost("pd_read_csv");
		var r = FsGrant.resolve("pd_read_csv", grants, path, false);
		#if (sys || nodejs)
		if (!sys.FileSystem.exists(r.nativeAbs) || sys.FileSystem.isDirectory(r.nativeAbs))
			throw new IoDenied("pd_read_csv", 'not a file: ${r.museAbs}');
		var text = sys.io.File.getContent(r.nativeAbs);
		return parse(text);
		#else
		throw new IoDenied("pd_read_csv", "filesystem unavailable on this host");
		#end
	}

	/** Parse CSV text (no IO). First row = header. */
	public static function parse(text:String):DataFrame {
		if (text == null || text.length == 0) return DataFrame.empty();
		var lines = splitLines(text);
		if (lines.length == 0) return DataFrame.empty();
		var header = parseRow(lines[0]);
		if (header.length == 0) return DataFrame.empty();
		var nCols = header.length;
		var rawRows:Array<Array<String>> = [];
		for (li in 1...lines.length) {
			var line = lines[li];
			if (StringTools.trim(line).length == 0) continue;
			var cells = parseRow(line);
			var row:Array<String> = [];
			for (c in 0...nCols) row.push(c < cells.length ? cells[c] : "");
			rawRows.push(row);
		}
		var n = rawRows.length;
		var isStr:Array<Bool> = [for (_ in 0...nCols) false];
		for (c in 0...nCols) {
			for (r in 0...n) {
				if (!cellLooksNumeric(rawRows[r][c])) {
					isStr[c] = true;
					break;
				}
			}
		}
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (c in 0...nCols) {
			var name = header[c];
			if (isStr[c]) {
				var labels:Array<String> = [];
				for (r in 0...n) labels.push(strCell(rawRows[r][c]));
				sOrder.push(name);
				sMap.set(name, labels);
			} else {
				var col = NdArrayF64.empty([n]);
				for (r in 0...n) col.setFlat(r, parseCell(rawRows[r][c]));
				order.push(name);
				map.set(name, col);
			}
		}
		return DataFrame.fromColumns(map, Index.range(n), order, sMap, sOrder);
	}

	/** Empty / NA / parseable float → numeric-looking; else → Str. */
	public static function cellLooksNumeric(raw:String):Bool {
		var s = StringTools.trim(raw != null ? raw : "");
		if (s.length == 0 || isNaToken(s)) return true;
		var f = Std.parseFloat(s);
		if (Math.isNaN(f)) return false;
		return floatStringLooksComplete(s);
	}

	/** Shared with Parquet fromObjects — reject partial `parseFloat` prefixes. */
	public static function floatStringLooksComplete(s:String):Bool {
		var t = StringTools.trim(s);
		if (t.length == 0) return false;
		var i = 0;
		if (t.charCodeAt(0) == 43 || t.charCodeAt(0) == 45) i = 1;
		if (i >= t.length) return false;
		var sawDigit = false;
		var sawDot = false;
		while (i < t.length) {
			var c = t.charCodeAt(i);
			if (c >= 48 && c <= 57) {
				sawDigit = true;
				i++;
			} else if (c == 46 && !sawDot) {
				sawDot = true;
				i++;
			} else if ((c == 101 || c == 69) && sawDigit) {
				i++;
				if (i < t.length && (t.charCodeAt(i) == 43 || t.charCodeAt(i) == 45)) i++;
				var expDigit = false;
				while (i < t.length && t.charCodeAt(i) >= 48 && t.charCodeAt(i) <= 57) {
					expDigit = true;
					i++;
				}
				return expDigit && i == t.length;
			} else {
				return false;
			}
		}
		return sawDigit;
	}

	static function strCell(raw:String):String {
		var s = StringTools.trim(raw != null ? raw : "");
		if (s.length == 0 || isNaToken(s)) return "";
		return s;
	}

	static function isNaToken(s:String):Bool {
		return s == "nan" || s == "NaN" || s == "NA" || s == "null" || s == "None";
	}

	static function parseCell(raw:String):Float {
		var s = StringTools.trim(raw != null ? raw : "");
		if (s.length == 0 || isNaToken(s)) return Math.NaN;
		var f = Std.parseFloat(s);
		return Math.isNaN(f) ? Math.NaN : f;
	}

	static function splitLines(text:String):Array<String> {
		var norm = StringTools.replace(text, "\r\n", "\n");
		norm = StringTools.replace(norm, "\r", "\n");
		return norm.split("\n");
	}

	/** Minimal CSV row split — supports quoted fields with commas. */
	static function parseRow(line:String):Array<String> {
		var out:Array<String> = [];
		var cur = new StringBuf();
		var i = 0;
		var inQ = false;
		while (i < line.length) {
			var ch = line.charAt(i);
			if (inQ) {
				if (ch == '"') {
					if (i + 1 < line.length && line.charAt(i + 1) == '"') {
						cur.add('"');
						i += 2;
						continue;
					}
					inQ = false;
					i++;
					continue;
				}
				cur.add(ch);
				i++;
			} else {
				if (ch == '"') {
					inQ = true;
					i++;
				} else if (ch == ",") {
					out.push(cur.toString());
					cur = new StringBuf();
					i++;
				} else {
					cur.add(ch);
					i++;
				}
			}
		}
		out.push(cur.toString());
		return out;
	}

	static function ensureFsHost(op:String):Void {
		#if !(sys || nodejs)
		throw new IoDenied(op, "filesystem unavailable on this host");
		#end
	}
}
