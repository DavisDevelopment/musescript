package musescript.harness;

/**
 * Offline multi-symbol panel loaders for CLI / evo (no live EDGAR/network).
 *
 * Accepts the same shapes callers already produce by hand:
 *   - JSON bySym `{ "AAPL": [ {open,high,low,close,volume,time,?data}, ... ], ... }`
 *     (see `tools/fund_panel_loader.py` / `tools/run_universe_scan.js`)
 *   - `SYM=path.csv,SYM=path.csv` tapes specs (PanelRunner / GeneRunner `--tapes`)
 *   - Long CSV with a `symbol` column (+ OHLCV)
 *   - Directory of per-symbol `*.csv` files (basename → symbol)
 *
 * SQLite/DuckDB equities DBs are pre-joined offline via `fund_panel_loader.py`
 * into JSON — this loader consumes the JSON, not the network crawl.
 */
class PanelLoader {
	/**
	 * Auto-detect format from `path`: directory → per-symbol CSVs;
	 * `.json` / object-looking text → bySym JSON; else long CSV (must have `symbol`).
	 */
	public static function load(path:String):PanelFeed {
		return PanelFeed.fromSymbolBars(loadMap(path));
	}

	public static function loadMap(path:String):Map<String, Array<Bar>> {
		if (path == null || StringTools.trim(path) == "")
			throw "PanelLoader: empty path";
		#if (!js || node)
		if (isDirectory(path)) return fromDirectoryMap(path);
		#end
		var text = readFile(path);
		return parseAuto(text, path);
	}

	/** `AAPL=a.csv,MSFT=b.csv` — each path is a single-symbol OHLCV CSV. */
	public static function fromTapesSpec(spec:String):PanelFeed {
		return PanelFeed.fromSymbolBars(fromTapesSpecMap(spec));
	}

	public static function fromTapesSpecMap(spec:String):Map<String, Array<Bar>> {
		if (spec == null || StringTools.trim(spec) == "")
			throw "PanelLoader: empty --tapes spec";
		var bySym = new Map<String, Array<Bar>>();
		for (part in spec.split(",")) {
			var s = StringTools.trim(part);
			if (s == "") continue;
			var eq = s.indexOf("=");
			if (eq <= 0 || eq == s.length - 1)
				throw 'PanelLoader: bad tapes entry "$s" (want SYM=path)';
			var sym = StringTools.trim(s.substr(0, eq));
			var p = StringTools.trim(s.substr(eq + 1));
			var bars = OhlcvCsv.parse(readFile(p));
			if (bars.length == 0)
				throw 'PanelLoader: tape for $sym at $p parsed to 0 bars';
			bySym.set(sym, bars);
		}
		if (!bySym.keys().hasNext())
			throw "PanelLoader: --tapes parsed to no symbols";
		return bySym;
	}

	/** fund_panel_loader / MuseRuntime.runPanel JSON text. */
	public static function fromJson(text:String):PanelFeed {
		return PanelFeed.fromSymbolBars(fromJsonMap(text));
	}

	public static function fromJsonMap(text:String):Map<String, Array<Bar>> {
		var root:Dynamic = haxe.Json.parse(text);
		if (root == null || !Reflect.isObject(root) || Std.isOfType(root, Array))
			throw "PanelLoader: JSON panel must be { SYM: bars[], ... }";
		var bySym = new Map<String, Array<Bar>>();
		for (sym in Reflect.fields(root)) {
			var raw:Dynamic = Reflect.field(root, sym);
			if (!Std.isOfType(raw, Array)) continue;
			var bars = barsFromDyn(cast raw);
			if (bars.length > 0) bySym.set(sym, bars);
		}
		if (!bySym.keys().hasNext())
			throw "PanelLoader: JSON panel has no symbol series";
		return bySym;
	}

	/** Long OHLCV CSV with a `symbol` (or `ticker` / `sym`) column. */
	public static function fromLongCsv(text:String):PanelFeed {
		return PanelFeed.fromSymbolBars(fromLongCsvMap(text));
	}

	public static function fromLongCsvMap(text:String):Map<String, Array<Bar>> {
		var lines = splitLines(text);
		if (lines.length < 2) throw "PanelLoader: long CSV needs header + rows";
		var header = splitCsv(lines[0]);
		var lower = [for (h in header) StringTools.trim(h).toLowerCase()];
		var symIdx = indexOfAny(lower, ["symbol", "ticker", "sym"]);
		if (symIdx < 0)
			throw "PanelLoader: long CSV requires a symbol/ticker column (or use bySym JSON / --tapes)";
		var open = indexOfAny(lower, ["open", "o"]);
		var high = indexOfAny(lower, ["high", "h"]);
		var low = indexOfAny(lower, ["low", "l"]);
		var close = indexOfAny(lower, ["close", "adj close", "adj_close", "c"]);
		var volume = indexOfAny(lower, ["volume", "vol", "v"]);
		var time = indexOfAny(lower, ["time", "date", "timestamp", "datetime", "ts"]);
		if (open < 0 || high < 0 || low < 0 || close < 0)
			throw "PanelLoader: long CSV needs open/high/low/close columns";

		var auxCols:Array<{i:Int, name:String}> = [];
		for (i in 0...lower.length) {
			if (i == symIdx || i == open || i == high || i == low || i == close || i == volume || i == time)
				continue;
			if (lower[i] == "" || lower[i] == "date") continue;
			auxCols.push({ i: i, name: lower[i] });
		}

		var bySym = new Map<String, Array<Bar>>();
		var idxBySym = new Map<String, Int>();
		for (li in 1...lines.length) {
			var line = StringTools.trim(lines[li]);
			if (line == "" || StringTools.startsWith(line, "#")) continue;
			var parts = splitCsv(line);
			if (symIdx >= parts.length) continue;
			var sym = StringTools.trim(parts[symIdx]);
			if (sym == "") continue;
			if (open >= parts.length || high >= parts.length || low >= parts.length || close >= parts.length)
				continue;
			var o = Std.parseFloat(StringTools.trim(parts[open]));
			var h = Std.parseFloat(StringTools.trim(parts[high]));
			var l = Std.parseFloat(StringTools.trim(parts[low]));
			var c = Std.parseFloat(StringTools.trim(parts[close]));
			if (!Math.isFinite(o) || !Math.isFinite(h) || !Math.isFinite(l) || !Math.isFinite(c)) continue;
			var v = volume >= 0 && volume < parts.length ? Std.parseFloat(StringTools.trim(parts[volume])) : 0.0;
			if (!Math.isFinite(v)) v = 0.0;
			var iSym = idxBySym.exists(sym) ? idxBySym.get(sym) : 0;
			var t = time >= 0 && time < parts.length
				? parseTime(parts[time], iSym)
				: (iSym : Float);
			var aux:Map<String, Float> = null;
			for (a in auxCols) {
				if (a.i >= parts.length) continue;
				if (aux == null) aux = new Map();
				aux.set(a.name, Std.parseFloat(StringTools.trim(parts[a.i])));
			}
			var bar:Bar = { open: o, high: h, low: l, close: c, volume: v, time: t, index: iSym };
			if (aux != null) bar.data = aux;
			if (!bySym.exists(sym)) bySym.set(sym, []);
			bySym.get(sym).push(bar);
			idxBySym.set(sym, iSym + 1);
		}
		if (!bySym.keys().hasNext())
			throw "PanelLoader: long CSV produced no symbol bars";
		return bySym;
	}

	#if (!js || node)
	public static function fromDirectory(dir:String):PanelFeed {
		return PanelFeed.fromSymbolBars(fromDirectoryMap(dir));
	}

	public static function fromDirectoryMap(dir:String):Map<String, Array<Bar>> {
		var bySym = new Map<String, Array<Bar>>();
		for (name in listFiles(dir)) {
			if (!StringTools.endsWith(name.toLowerCase(), ".csv")) continue;
			var sym = name.substr(0, name.length - 4);
			if (sym == "") continue;
			var bars = OhlcvCsv.parse(readFile(joinPath(dir, name)));
			if (bars.length > 0) bySym.set(sym.toUpperCase(), bars);
		}
		if (!bySym.keys().hasNext())
			throw 'PanelLoader: no *.csv files in $dir';
		return bySym;
	}
	#end

	/** Anonymous `{ SYM: bars[] }` for `MuseRuntime.runPanel` / JS callers. */
	public static function toBySymDyn(bySym:Map<String, Array<Bar>>):Dynamic {
		var o:Dynamic = {};
		for (sym => bars in bySym) Reflect.setField(o, sym, barsToDyn(bars));
		return o;
	}

	public static function panelToBySymDyn(panel:PanelFeed):Dynamic {
		// Rebuild from packed columns so callers don't need the original map.
		var bySym = new Map<String, Array<Bar>>();
		var n = panel.length();
		for (sym in panel.symbols) bySym.set(sym, []);
		for (t in 0...n) {
			var time = t < panel.times.length ? panel.times[t] : t * 1.0;
			for (sym in panel.symbols) {
				var c = panel.closes[t].exists(sym) ? panel.closes[t].get(sym) : Math.NaN;
				var o = panel.opens[t].exists(sym) ? panel.opens[t].get(sym) : c;
				var h = panel.highs[t].exists(sym) ? panel.highs[t].get(sym) : c;
				var l = panel.lows[t].exists(sym) ? panel.lows[t].get(sym) : c;
				var v = panel.volumes[t].exists(sym) ? panel.volumes[t].get(sym) : 0.0;
				if (!Math.isFinite(c)) continue; // skip missing session for this name
				var bar:Bar = { open: o, high: h, low: l, close: c, volume: v, time: time, index: bySym.get(sym).length };
				if (panel.auxFieldNames != null && panel.auxFieldNames.length > 0) {
					var data = new Map<String, Float>();
					for (f in panel.auxFieldNames) {
						var series = panel.auxSeries.get(f);
						if (series == null || t >= series.length) continue;
						var row = series[t];
						if (row != null && row.exists(sym)) data.set(f, row.get(sym));
					}
					if (data.keys().hasNext()) bar.data = data;
				}
				bySym.get(sym).push(bar);
			}
		}
		return toBySymDyn(bySym);
	}

	static function parseAuto(text:String, path:String):Map<String, Array<Bar>> {
		var trimmed = StringTools.trim(text);
		if (trimmed == "") throw 'PanelLoader: empty file $path';
		var lowerPath = path.toLowerCase();
		if (StringTools.endsWith(lowerPath, ".json") || trimmed.charAt(0) == "{")
			return fromJsonMap(text);
		return fromLongCsvMap(text);
	}

	static function barsFromDyn(raw:Array<Dynamic>):Array<Bar> {
		var out:Array<Bar> = [];
		for (i in 0...raw.length) {
			var d:Dynamic = raw[i];
			if (d == null) continue;
			var o = f(d, "open");
			var h = f(d, "high");
			var l = f(d, "low");
			var c = f(d, "close");
			if (!Math.isFinite(o) || !Math.isFinite(h) || !Math.isFinite(l) || !Math.isFinite(c)) continue;
			var v = Reflect.hasField(d, "volume") ? f(d, "volume") : 0.0;
			if (!Math.isFinite(v)) v = 0.0;
			var t = Reflect.hasField(d, "time") ? f(d, "time") : (i : Float);
			if (!Math.isFinite(t)) t = i;
			var bar:Bar = { open: o, high: h, low: l, close: c, volume: v, time: t, index: i };
			if (Reflect.hasField(d, "data") && Reflect.field(d, "data") != null) {
				var dataObj:Dynamic = Reflect.field(d, "data");
				var data = new Map<String, Float>();
				for (k in Reflect.fields(dataObj)) {
					var fv = Std.parseFloat(Std.string(Reflect.field(dataObj, k)));
					if (Math.isFinite(fv)) data.set(k, fv);
				}
				if (data.keys().hasNext()) bar.data = data;
			}
			out.push(bar);
		}
		return out;
	}

	static function barsToDyn(bars:Array<Bar>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		for (b in bars) {
			var row:Dynamic = {
				open: b.open, high: b.high, low: b.low, close: b.close,
				volume: b.volume, time: b.time, index: b.index
			};
			if (b.data != null) {
				var data:Dynamic = {};
				for (k => v in b.data) Reflect.setField(data, k, v);
				Reflect.setField(row, "data", data);
			}
			out.push(row);
		}
		return out;
	}

	static inline function f(d:Dynamic, name:String):Float {
		return Reflect.hasField(d, name) ? Std.parseFloat(Std.string(Reflect.field(d, name))) : Math.NaN;
	}

	static function indexOfAny(lower:Array<String>, names:Array<String>):Int {
		for (i in 0...lower.length)
			for (n in names)
				if (lower[i] == n) return i;
		return -1;
	}

	static function parseTime(s:String, fallback:Int):Float {
		var t = StringTools.trim(s);
		var asNum = Std.parseFloat(t);
		if (Math.isFinite(asNum) && t.indexOf("-") < 0) return asNum;
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
		return text.split("\r\n").join("\n").split("\r").join("\n").split("\n");
	}

	static function splitCsv(line:String):Array<String> {
		var out:Array<String> = [];
		var cur = new StringBuf();
		var inQ = false;
		for (i in 0...line.length) {
			var ch = line.charAt(i);
			if (ch == '"') { inQ = !inQ; continue; }
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

	static function readFile(path:String):String {
		#if js
		return js.Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
		#elseif python
		return python.Syntax.code("open({0}, 'r', encoding='utf-8').read()", path);
		#else
		return sys.io.File.getContent(path);
		#end
	}

	static function isDirectory(path:String):Bool {
		#if js
		try {
			return js.Syntax.code("require('fs').statSync({0}).isDirectory()", path);
		} catch (_:Dynamic) {
			return false;
		}
		#else
		return sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path);
		#end
	}

	static function listFiles(dir:String):Array<String> {
		#if js
		var arr:Array<String> = js.Syntax.code("require('fs').readdirSync({0})", dir);
		return arr != null ? arr : [];
		#else
		return sys.FileSystem.readDirectory(dir);
		#end
	}

	static function joinPath(dir:String, name:String):String {
		if (dir.length > 0 && (dir.charAt(dir.length - 1) == "/" || dir.charAt(dir.length - 1) == "\\"))
			return dir + name;
		return dir + "/" + name;
	}
}
