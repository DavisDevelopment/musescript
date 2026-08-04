package musescript.dataframe;

import musescript.io.FsGrant;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.ndarray.NdArrayF64;

/**
 * Grant-gated CSV → DataFrame (M1 ingest tier).
 *
 * Parses numeric columns as F64 (non-numeric / empty → NaN). Header required.
 * Fitness / null grants → {@link IoDenied}.
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
		var rows:Array<Array<Float>> = [];
		for (li in 1...lines.length) {
			var line = lines[li];
			if (StringTools.trim(line).length == 0) continue;
			var cells = parseRow(line);
			var row:Array<Float> = [];
			for (c in 0...nCols) {
				var raw = c < cells.length ? cells[c] : "";
				row.push(parseCell(raw));
			}
			rows.push(row);
		}
		var n = rows.length;
		var map = new Map<String, NdArrayF64>();
		for (c in 0...nCols) {
			var col = NdArrayF64.empty([n]);
			for (r in 0...n) col.setFlat(r, rows[r][c]);
			map.set(header[c], col);
		}
		return DataFrame.fromColumns(map, Index.range(n), header);
	}

	static function parseCell(raw:String):Float {
		var s = StringTools.trim(raw);
		if (s.length == 0 || s == "nan" || s == "NaN" || s == "NA" || s == "null")
			return Math.NaN;
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
