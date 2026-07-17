package musescript.harness;

/**
 * Load OHLCV bars from a CSV file.
 * Accepts headered files with columns containing open/high/low/close/volume
 * (case-insensitive). Optional time/date and symbol columns are ignored for pricing.
 * Extra columns are captured in auxiliaryColumns (indexed by bar index).
 */
class OhlcvCsv {
	/** Store auxiliary (non-OHLCV) columns from the last parse, keyed by bar index. */
	public static var auxiliaryColumns:Map<Int, Map<String, Float>> = new Map();
	public static var auxiliaryNames:Array<String> = [];

	public static function load(path:String):Array<Bar> {
		var text = readFile(path);
		if (text == null || StringTools.trim(text) == "")
			throw 'OhlcvCsv: empty or missing file $path';
		return parse(text);
	}

	/** Load CSV if present; otherwise return `BarFeed.synthetic(fallbackN, seed).all()`. */
	public static function loadOrSynthetic(path:String, fallbackN:Int, ?seed:Int = 42):Array<Bar> {
		if (fileExists(path)) return load(path);
		return BarFeed.synthetic(fallbackN, seed).all();
	}

	public static function parse(text:String):Array<Bar> {
		var lines = splitLines(text);
		if (lines.length == 0) return [];
		var start = 0;
		var col = detectColumns(lines[0]);
		if (col.hasHeader) start = 1;

		// Clear previous auxiliary column state
		auxiliaryColumns = new Map();
		auxiliaryNames = [];

		// Resolve auxiliary (non-OHLCV/time/symbol) header columns ONCE, not per row.
		var auxCols:Array<{i:Int, name:String}> = [];
		if (col.hasHeader) {
			var headerParts = splitCsv(lines[0]);
			for (i in 0...headerParts.length) {
				if (i == col.open || i == col.high || i == col.low || i == col.close
					|| i == col.volume || i == col.time) continue;
				var hdr = StringTools.trim(headerParts[i]).toLowerCase();
				if (hdr == "" || hdr == "symbol" || hdr == "date") continue;
				auxCols.push({ i: i, name: hdr });
				if (auxiliaryNames.indexOf(hdr) < 0) auxiliaryNames.push(hdr);
			}
		}

		var bars:Array<Bar> = [];
		var idx = 0;
		for (li in start...lines.length) {
			var line = StringTools.trim(lines[li]);
			if (line == "" || StringTools.startsWith(line, "#")) continue;
			var parts = splitCsv(line);
			if (parts.length < 5) continue;
			var o = parseFloat(parts[col.open]);
			var h = parseFloat(parts[col.high]);
			var l = parseFloat(parts[col.low]);
			var c = parseFloat(parts[col.close]);
			var v = col.volume >= 0 && col.volume < parts.length ? parseFloat(parts[col.volume]) : 0;
			var t = col.time >= 0 && col.time < parts.length ? parseTime(parts[col.time], idx) : (idx:Float);
			if (!Math.isFinite(o) || !Math.isFinite(h) || !Math.isFinite(l) || !Math.isFinite(c)) continue;

			var auxData:Map<String, Float> = null;
			for (a in auxCols) {
				if (a.i >= parts.length) continue;
				if (auxData == null) auxData = new Map();
				auxData.set(a.name, parseFloat(parts[a.i]));
			}

			var bar:Bar = { open: o, high: h, low: l, close: c, volume: v, time: t, index: idx };
			if (auxData != null) {
				bar.data = auxData;
				auxiliaryColumns.set(idx, auxData);
			}
			bars.push(bar);
			idx++;
		}
		return bars;
	}

	static function detectColumns(firstLine:String):{hasHeader:Bool, open:Int, high:Int, low:Int, close:Int, volume:Int, time:Int} {
		var parts = splitCsv(firstLine);
		var lower = [for (p in parts) StringTools.trim(p).toLowerCase()];
		function find(names:Array<String>):Int {
			// Exact matches win over prefix fallback: with auxiliary columns in
			// play, "volatility" must not hijack volume nor "oi" hijack open.
			for (i in 0...lower.length)
				for (n in names)
					if (lower[i] == n) return i;
			for (i in 0...lower.length)
				for (n in names)
					if (StringTools.startsWith(lower[i], n)) return i;
			return -1;
		}
		var o = find(["open", "o"]);
		var h = find(["high", "h"]);
		var l = find(["low", "l"]);
		var c = find(["close", "adj close", "adj_close", "c"]);
		var v = find(["volume", "vol", "v"]);
		var t = find(["time", "date", "timestamp", "datetime", "ts"]);
		var hasHeader = o >= 0 && h >= 0 && l >= 0 && c >= 0;
		if (!hasHeader) {
			// positional: [date?,] open, high, low, close [, volume]
			var looksDate = parts.length > 0 && parts[0].indexOf("-") >= 0;
			var base = looksDate ? 1 : 0;
			return {
				hasHeader: false,
				open: base,
				high: base + 1,
				low: base + 2,
				close: base + 3,
				volume: parts.length > base + 4 ? base + 4 : -1,
				time: looksDate ? 0 : -1
			};
		}
		return { hasHeader: true, open: o, high: h, low: l, close: c, volume: v, time: t };
	}

	static function parseFloat(s:String):Float {
		return Std.parseFloat(StringTools.trim(s));
	}

	static function parseTime(s:String, fallback:Int):Float {
		var t = StringTools.trim(s);
		var asNum = Std.parseFloat(t);
		if (Math.isFinite(asNum) && t.indexOf("-") < 0) return asNum;
		// YYYY-MM-DD → crude day ordinal
		var bits = t.split("-");
		if (bits.length >= 3) {
			var y = Std.parseInt(bits[0]);
			var m = Std.parseInt(bits[1]);
			var d = Std.parseInt(bits[2].substr(0, 2));
			if (y != null && m != null && d != null)
				return y * 372 + m * 31 + d;
		}
		return fallback;
	}

	static function splitLines(text:String):Array<String> {
		var norm = text.split("\r\n").join("\n").split("\r").join("\n");
		return norm.split("\n");
	}

	static function splitCsv(line:String):Array<String> {
		var out:Array<String> = [];
		var cur = new StringBuf();
		var inQ = false;
		for (i in 0...line.length) {
			var ch = line.charAt(i);
			if (ch == '"') {
				inQ = !inQ;
				continue;
			}
			if (ch == "," && !inQ) {
				out.push(cur.toString());
				cur = new StringBuf();
				continue;
			}
			cur.add(ch);
		}
		out.push(cur.toString());
		return out;
	}

	public static function exists(path:String):Bool {
		return fileExists(path);
	}

	static function fileExists(path:String):Bool {
		#if js
		try {
			return js.Syntax.code("require('fs').existsSync({0})", path);
		} catch (_:Dynamic) {
			return false;
		}
		#elseif python
		try {
			return python.Syntax.code("__import__('os').path.isfile({0})", path);
		} catch (_:Dynamic) {
			return false;
		}
		#else
		return sys.FileSystem.exists(path);
		#end
	}

	static function readFile(path:String):String {
		#if js
		return js.Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
		#elseif python
		return python.Syntax.code("open({0}, 'r', encoding='utf-8').read()", path);
		#else
		return sys.io.File.getContent(path);
		#end
	}
}
