package musescript.harness;

/**
 * Calendar-aligned multi-symbol OHLCV feed.
 *
 * Each step is one session index shared across the universe. Missing names on
 * a given day are NaN in the price maps (strategies should gate with
 * `sym_available`). The yielded `Bar` is a session marker (time/index); its
 * OHLCV fields are the first live symbol's prices that day (handy for
 * single-series builtins that still read `close`).
 */
class PanelFeed {
	public var symbols:Array<String>;
	/** Session times (same length as bars). */
	public var times:Array<Float>;
	/** Per-session closes keyed by symbol — parallel to `bars`. */
	public var closes:Array<Map<String, Float>>;
	public var opens:Array<Map<String, Float>>;
	public var highs:Array<Map<String, Float>>;
	public var lows:Array<Map<String, Float>>;
	public var volumes:Array<Map<String, Float>>;
	/**
	 * Auxiliary (non-OHLCV) per-symbol fields — e.g. PIT fundamentals — sourced
	 * from each input Bar's `.data` map, keyed the same way as opens/closes:
	 * `auxSeries.get(fieldName)[t].get(sym)`. Built once at construction from
	 * whatever values the loader already forward-filled/NaN-gated per bar
	 * (this class does no filling of its own); consumed causally, one `t` row
	 * at a time, by HarnessContext.observePanel — never preloaded in bulk. */
	public var auxSeries:Map<String, Array<Map<String, Float>>>;
	public var auxFieldNames:Array<String>;
	var bars:Array<Bar>;
	var i:Int;

	public function new(
		symbols:Array<String>,
		times:Array<Float>,
		opens:Array<Map<String, Float>>,
		highs:Array<Map<String, Float>>,
		lows:Array<Map<String, Float>>,
		closes:Array<Map<String, Float>>,
		volumes:Array<Map<String, Float>>
	) {
		this.symbols = symbols != null ? symbols : [];
		this.times = times != null ? times : [];
		this.opens = opens != null ? opens : [];
		this.highs = highs != null ? highs : [];
		this.lows = lows != null ? lows : [];
		this.closes = closes != null ? closes : [];
		this.volumes = volumes != null ? volumes : [];
		this.auxSeries = new Map();
		this.auxFieldNames = [];
		this.bars = buildSessionBars();
		this.i = 0;
	}

	function buildSessionBars():Array<Bar> {
		var out:Array<Bar> = [];
		var n = closes.length;
		for (t in 0...n) {
			var cMap = closes[t];
			var oMap = t < opens.length ? opens[t] : cMap;
			var hMap = t < highs.length ? highs[t] : cMap;
			var lMap = t < lows.length ? lows[t] : cMap;
			var vMap = t < volumes.length ? volumes[t] : null;
			var o = Math.NaN, h = Math.NaN, l = Math.NaN, c = Math.NaN, v = 0.0;
			for (sym in symbols) {
				if (cMap != null && cMap.exists(sym)) {
					var cv = cMap.get(sym);
					if (cv > 0 && !Math.isNaN(cv)) {
						c = cv;
						o = oMap != null && oMap.exists(sym) ? oMap.get(sym) : cv;
						h = hMap != null && hMap.exists(sym) ? hMap.get(sym) : cv;
						l = lMap != null && lMap.exists(sym) ? lMap.get(sym) : cv;
						v = vMap != null && vMap.exists(sym) ? vMap.get(sym) : 0.0;
						break;
					}
				}
			}
			var time = t < times.length ? times[t] : t * 1.0;
			out.push({ open: o, high: h, low: l, close: c, volume: v, time: time, index: t });
		}
		return out;
	}

	public function length():Int return bars.length;

	public function all():Array<Bar> return bars;

	public function asBarFeed():BarFeed return new BarFeed(bars);

	public function pricesAt(t:Int):Map<String, Float> {
		return t >= 0 && t < closes.length ? closes[t] : new Map();
	}

	/**
	 * Build a panel from per-symbol bar arrays aligned by `Bar.time`
	 * (falling back to bar index when times collide / are missing).
	 */
	public static function fromSymbolBars(bySym:Map<String, Array<Bar>>):PanelFeed {
		var syms:Array<String> = [];
		for (s in bySym.keys()) syms.push(s);
		syms.sort(Reflect.compare);

		var timeSet = new Map<String, Bool>();
		var timeOrder:Array<Float> = [];
		for (sym in syms) {
			var arr = bySym.get(sym);
			if (arr == null) continue;
			for (b in arr) {
				var key = Std.string(b.time);
				if (!timeSet.exists(key)) {
					timeSet.set(key, true);
					timeOrder.push(b.time);
				}
			}
		}
		timeOrder.sort(Reflect.compare);

		var opens:Array<Map<String, Float>> = [];
		var highs:Array<Map<String, Float>> = [];
		var lows:Array<Map<String, Float>> = [];
		var closes:Array<Map<String, Float>> = [];
		var volumes:Array<Map<String, Float>> = [];

		// index: sym -> time -> bar
		var lookup = new Map<String, Map<String, Bar>>();
		for (sym in syms) {
			var m = new Map<String, Bar>();
			var arr = bySym.get(sym);
			if (arr != null) for (b in arr) m.set(Std.string(b.time), b);
			lookup.set(sym, m);
		}

		for (t in timeOrder) {
			var key = Std.string(t);
			var oM = new Map<String, Float>();
			var hM = new Map<String, Float>();
			var lM = new Map<String, Float>();
			var cM = new Map<String, Float>();
			var vM = new Map<String, Float>();
			for (sym in syms) {
				var bm = lookup.get(sym);
				var b = bm != null ? bm.get(key) : null;
				if (b != null) {
					oM.set(sym, b.open);
					hM.set(sym, b.high);
					lM.set(sym, b.low);
					cM.set(sym, b.close);
					vM.set(sym, b.volume);
				} else {
					oM.set(sym, Math.NaN);
					hM.set(sym, Math.NaN);
					lM.set(sym, Math.NaN);
					cM.set(sym, Math.NaN);
					vM.set(sym, Math.NaN);
				}
			}
			opens.push(oM);
			highs.push(hM);
			lows.push(lM);
			closes.push(cM);
			volumes.push(vM);
		}
		var pf = new PanelFeed(syms, timeOrder, opens, highs, lows, closes, volumes);

		// Discover aux field names from any bar's `.data` map, then build one
		// per-t symbol map per field (NaN where the symbol/bar lacks that key,
		// e.g. before a fundamental's first filing date — the loader is the
		// PIT authority; this step only reshapes what it already provided).
		var auxFieldSet = new Map<String, Bool>();
		for (sym in syms) {
			var arr = bySym.get(sym);
			if (arr == null) continue;
			for (b in arr) {
				if (b.data != null) for (k in b.data.keys()) auxFieldSet.set(k, true);
			}
		}
		var auxNames:Array<String> = [for (k in auxFieldSet.keys()) k];
		auxNames.sort(Reflect.compare);
		var auxSeries = new Map<String, Array<Map<String, Float>>>();
		for (name in auxNames) {
			var perT:Array<Map<String, Float>> = [];
			for (t in timeOrder) {
				var key = Std.string(t);
				var m = new Map<String, Float>();
				for (sym in syms) {
					var bm = lookup.get(sym);
					var b = bm != null ? bm.get(key) : null;
					var v = (b != null && b.data != null && b.data.exists(name)) ? b.data.get(name) : Math.NaN;
					m.set(sym, v);
				}
				perT.push(m);
			}
			auxSeries.set(name, perT);
		}
		pf.auxFieldNames = auxNames;
		pf.auxSeries = auxSeries;
		return pf;
	}

	/** Synthetic correlated universe for tests / demos. */
	public static function synthetic(nSyms:Int = 8, nBars:Int = 120, ?seed:Int = 7):PanelFeed {
		var bySym = new Map<String, Array<Bar>>();
		var rng = seed;
		for (s in 0...nSyms) {
			var sym = "S" + StringTools.lpad(Std.string(s), "0", 2);
			var bars:Array<Bar> = [];
			var price = 50.0 + (s + 1) * 10.0;
			for (i in 0...nBars) {
				rng = (rng * 1103515245 + 12345) & 0x7fffffff;
				var noise = ((rng % 1000) / 1000.0 - 0.5) * 2.0;
				// mild shared drift so cross-section ranks move
				var shared = Math.sin(i / 11.0 + s * 0.3) * 0.004;
				var o = price;
				var c = price * (1 + noise * 0.012 + shared);
				var h = Math.max(o, c) * 1.002;
				var l = Math.min(o, c) * 0.998;
				var v = 1000.0 + (rng % 800);
				bars.push({ open: o, high: h, low: l, close: c, volume: v, time: i * 1.0, index: i });
				price = c;
			}
			bySym.set(sym, bars);
		}
		return fromSymbolBars(bySym);
	}
}
