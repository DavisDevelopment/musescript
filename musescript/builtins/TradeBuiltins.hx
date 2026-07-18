package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.runtime.MuseIters;
import musescript.runtime.IterDriver;
import musescript.runtime.Callables;
import musescript.runtime.MuseIter;
import musescript.runtime.IterResult;
import musescript.runtime.MergeIter;

/**
 * Trading / chart / math / iter builtins installed into MuseInterp globals.
 */
class TradeBuiltins {
	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("sma", sma.bind(harness));
		vars.set("ema", ema.bind(harness));
		vars.set("rsi", rsi.bind(harness));
		vars.set("atr", atr.bind(harness));
		vars.set("bbands", bbands.bind(harness));
		vars.set("macd", macd.bind(harness));
		vars.set("stoch", stoch.bind(harness));
		vars.set("vwap", vwap.bind(harness));
		vars.set("hl2", hl2.bind(harness));
		vars.set("hlc3", hlc3.bind(harness));
		vars.set("ohlc4", ohlc4.bind(harness));
		vars.set("crossover", crossover);
		vars.set("crossunder", crossunder);
		vars.set("highest", highest.bind(harness));
		vars.set("lowest", lowest.bind(harness));
		vars.set("change", change.bind(harness));
		vars.set("pct_change", pctChange.bind(harness));
		vars.set("nz", nz);
		vars.set("na", na);
		vars.set("roc", roc.bind(harness));
		vars.set("mom", mom.bind(harness));
		vars.set("stdev", stdev.bind(harness));
		vars.set("ewm_var", ewmVar.bind(harness));
		vars.set("ewm_stdev", ewmStdev.bind(harness));
		vars.set("wma", wma.bind(harness));
		vars.set("rma", rma.bind(harness));
		vars.set("rising", function(x:Float, n:Int, ?minBars:Int = 0) {
			if (minBars > 0) {
				var bi = harness.currentBar != null ? harness.currentBar.index : -1;
				if (harness.orders.barsInTrade(bi) < minBars) return false;
			}
			return rising(x, n);
		});
		vars.set("falling", function(x:Float, n:Int, ?minBars:Int = 0) {
			if (minBars > 0) {
				var bi = harness.currentBar != null ? harness.currentBar.index : -1;
				if (harness.orders.barsInTrade(bi) < minBars) return false;
			}
			return falling(x, n);
		});
		vars.set("window", window.bind(harness));
		vars.set("ohlcv_window", ohlcvWindow.bind(harness));
		vars.set("str_len", strLen);
		vars.set("str_slice", strSlice);
		vars.set("str_contains", strContains);
		vars.set("str_concat", strConcat);
		vars.set("str_to_float", strToFloat);
		vars.set("str_trim", StringBuiltins.trim);
		vars.set("str_lower", StringBuiltins.lower);
		vars.set("str_upper", StringBuiltins.upper);
		vars.set("str_starts_with", StringBuiltins.startsWith);
		vars.set("str_ends_with", StringBuiltins.endsWith);
		vars.set("str_index_of", StringBuiltins.indexOf);
		vars.set("str_replace", StringBuiltins.replace);
		vars.set("str_split", StringBuiltins.split);
		vars.set("str_join", StringBuiltins.join);
		vars.set("str_to_bool", StringBuiltins.toBool);
		vars.set("str_from_float", StringBuiltins.fromFloat);
		vars.set("str_from_bool", StringBuiltins.fromBool);
		vars.set("ml_dot", MlBuiltins.dot);
		vars.set("ml_sigmoid", MlBuiltins.sigmoid);
		vars.set("ml_softmax", MlBuiltins.softmax);
		vars.set("ml_mse", MlBuiltins.mse);
		vars.set("ml_mae", MlBuiltins.mae);
		vars.set("ml_linear_predict", MlBuiltins.linearPredict);
		vars.set("ml_ridge_fit", MlBuiltins.ridgeFit);
		vars.set("ml_matrix", MlBuiltins.matrix);
		vars.set("ml_matrix_rows", MlBuiltins.matrixRows);
		vars.set("ml_matrix_cols", MlBuiltins.matrixCols);
		vars.set("ml_matrix_data", MlBuiltins.matrixData);
		vars.set("ml_matrix_get", MlBuiltins.matrixGet);
		vars.set("ml_matrix_transpose", MlBuiltins.matrixTranspose);
		vars.set("ml_matrix_inverse", MlBuiltins.matrixInverse);
		vars.set("ml_matrix_determinant", MlBuiltins.matrixDeterminant);
		vars.set("ml_ridge_fit_matrix", MlBuiltins.ridgeFitMatrix);

		// `long(10)` = legacy immediate close-fill; `long({type:"limit", px:...})`
		// places on the pending book and fills on future bars (OrderBook.hx).
		vars.set("long", function(?arg:Dynamic) {
			if (harness.currentBar != null)
				harness.orders.submit("long", arg, harness.currentBar.close, harness.currentBar.index);
		});
		vars.set("short", function(?arg:Dynamic) {
			if (harness.currentBar != null)
				harness.orders.submit("short", arg, harness.currentBar.close, harness.currentBar.index);
		});
		vars.set("flat", function(?arg:Dynamic) {
			if (harness.currentBar != null)
				harness.orders.submit("flat", arg, harness.currentBar.close, harness.currentBar.index);
		});
		vars.set("orders_pending", function() return harness.orders.book.pendingCount());
		vars.set("orders_cancel_all", function() return harness.orders.book.cancelAll());
		vars.set("position", function() return harness.orders.positionSize());
		vars.set("entry_price", function() return harness.orders.entryPrice);
		vars.set("bars_in_trade", function() {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			return harness.orders.barsInTrade(bi);
		});
		vars.set("cash", function() return harness.orders.cash);
		vars.set("equity", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			return harness.orders.equityAt(px);
		});
		vars.set("unrealized_pnl", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			return harness.orders.unrealizedPnl(px);
		});

		vars.set("log", function(?a:Dynamic, ?b:Dynamic, ?c:Dynamic, ?d:Dynamic) {
			var parts:Array<String> = [];
			if (a != null) parts.push(Std.string(a));
			if (b != null) parts.push(Std.string(b));
			if (c != null) parts.push(Std.string(c));
			if (d != null) parts.push(Std.string(d));
			harness.pushLog(parts.join(" "));
		});
		vars.set("plot", function(series:Float, label:String, ?color:String) {
			var bi = harness.currentBar != null ? harness.currentBar.index : 0;
			harness.chart.plot(series, label, color, bi);
		});
		vars.set("plotshape", function(label:String) {
			var bi = harness.currentBar != null ? harness.currentBar.index : 0;
			harness.chart.plotshape(label, bi);
		});
		vars.set("hline", function(v:Float, label:String) harness.chart.hline(v, label));
		vars.set("bgcolor", function(color:String) {
			var bi = harness.currentBar != null ? harness.currentBar.index : 0;
			harness.chart.bgcolor(color, bi);
		});

		vars.set("clamp", function(x:Float, lo:Float, hi:Float) return Math.max(lo, Math.min(hi, x)));
		vars.set("zscore", zscore);
		vars.set("vector_zscore", zscore);
		vars.set("correlation", correlation);
		vars.set("sharpe", function(returns:Array<Float>) return musescript.harness.Metrics.sharpe(returns));
		vars.set("sortino", function(returns:Array<Float>) return musescript.harness.Metrics.sortino(returns));
		vars.set("max_drawdown", function(equity:Array<Float>) return musescript.harness.Metrics.maxDrawdown(equity));
		vars.set("stat_mean", StatsBuiltins.mean);
		vars.set("stat_median", StatsBuiltins.median);
		vars.set("stat_variance", StatsBuiltins.variance);
		vars.set("stat_sample_variance", StatsBuiltins.sampleVariance);
		vars.set("stat_stddev", StatsBuiltins.standardDeviation);
		vars.set("stat_sample_stddev", StatsBuiltins.sampleStandardDeviation);
		vars.set("stat_quantile", StatsBuiltins.quantile);
		vars.set("stat_covariance", StatsBuiltins.covariance);
		vars.set("stat_correlation", StatsBuiltins.pearson);
		vars.set("stat_skewness", StatsBuiltins.skewness);
		vars.set("stat_kurtosis", StatsBuiltins.kurtosis);
		vars.set("stat_rank", StatsBuiltins.rank);
		vars.set("stat_percentile_rank", StatsBuiltins.percentileRank);
		vars.set("stat_regression", StatsBuiltins.regression);
		vars.set("stat_autocorr", StatsBuiltins.autocorr);
		vars.set("sort", StatsBuiltins.sort);
		vars.set("argsort", StatsBuiltins.argsort);
		vars.set("stat_zscore", StatsBuiltins.zScores);
		vars.set("sci_cumsum", StatsBuiltins.cumulativeSum);
		vars.set("sci_diff", StatsBuiltins.difference);
		vars.set("sci_normalize", StatsBuiltins.normalize);

		vars.set("map", function(xs:Dynamic, f:Dynamic) {
			return IterDriver.map(MuseIters.from(xs), Callables.asHost1(f, harness));
		});
		vars.set("flatMap", function(xs:Dynamic, f:Dynamic) {
			return IterDriver.flatMap(MuseIters.from(xs), Callables.asHost1(f, harness));
		});
		vars.set("filter", function(xs:Dynamic, p:Dynamic) {
			return IterDriver.filter(MuseIters.from(xs), Callables.asHostPred(p, harness));
		});
		vars.set("any", function(xs:Dynamic, p:Dynamic) {
			return IterDriver.any(MuseIters.from(xs), Callables.asHostPred(p, harness));
		});
		vars.set("all", function(xs:Dynamic, p:Dynamic) {
			return IterDriver.all(MuseIters.from(xs), Callables.asHostPred(p, harness));
		});
		vars.set("find", function(xs:Dynamic, p:Dynamic) {
			return IterDriver.find(MuseIters.from(xs), Callables.asHost1(p, harness));
		});
		vars.set("sum", function(xs:Dynamic) {
			return IterDriver.sum(MuseIters.from(xs));
		});
		vars.set("count", function(xs:Dynamic) {
			return IterDriver.count(MuseIters.from(xs));
		});
		vars.set("min", function(xs:Dynamic) {
			return IterDriver.min(MuseIters.from(xs));
		});
		vars.set("max", function(xs:Dynamic) {
			return IterDriver.max(MuseIters.from(xs));
		});
		vars.set("avg", function(xs:Dynamic) {
			return IterDriver.avg(MuseIters.from(xs));
		});
		vars.set("take", function(xs:Dynamic, n:Int) {
			return IterDriver.take(MuseIters.from(xs), n);
		});
		vars.set("drop", function(xs:Dynamic, n:Int) {
			return IterDriver.drop(MuseIters.from(xs), n);
		});
		vars.set("takeWhile", function(xs:Dynamic, p:Dynamic) {
			return IterDriver.takeWhile(MuseIters.from(xs), Callables.asHostPred(p, harness));
		});
		vars.set("scan", function(xs:Dynamic, init:Dynamic, f:Dynamic) {
			return IterDriver.scan(MuseIters.from(xs), init, Callables.asHost2(f, harness));
		});
		vars.set("reduce", function(xs:Dynamic, init:Dynamic, f:Dynamic) {
			return IterDriver.reduce(MuseIters.from(xs), init, Callables.asHost2(f, harness));
		});
		vars.set("range", function(a:Int, ?b:Int) {
			return b == null ? IterDriver.range(0, a) : IterDriver.range(a, b);
		});
		vars.set("enumerate", function(xs:Dynamic) {
			return IterDriver.enumerate(MuseIters.from(xs));
		});
		vars.set("merge", merge);
		vars.set("zip", zip);
		vars.set("zipWith", function(a:Dynamic, b:Dynamic, f:Dynamic) {
			return zipWith(a, b, Callables.asHost2(f, harness));
		});

		vars.set("params", {
			register: function(name:String, value:Dynamic, ?min:Float, ?max:Float, ?step:Float, ?tune:String) {
				harness.params.register(name, value, min, max, step, tune);
			},
			get: function(name:String) return harness.params.get(name),
			set: function(name:String, v:Dynamic) harness.params.set(name, v)
		});
		vars.set("indicators", {
			register: function(name:String, factory:Dynamic) harness.indicators.register(name, factory),
			get: function(name:String) return harness.indicators.get(name)
		});

		/*
		.install the builtin modules that are not specific to trading, but are useful for general-purpose programming and data analysis. 
		These include graph algorithms, dictionary and set operations, portfolio management, and bag (multiset) operations.
		*/
		GraphBuiltins.install(vars);
		DictBuiltins.install(vars);
		SetBuiltins.install(vars);
		PortfolioBuiltins.install(vars, harness);
		BagBuiltins.install(vars, harness);

		// yass queen, dat universe :D
		vars.set("universe", harness.universe);

		// expose the Math object directly... are there other objects we should perhaps expose as well?
		vars.set("Math", Math);
	}

	static function seriesVals(harness:HarnessContext, src:Dynamic, len:Int):Array<Float> {
		if (Std.isOfType(src, String)) {
			var name:String = cast src;
			var a = harness.series.get(name);
			if (a == null) return [];
			return a.slice(Std.int(Math.max(0, a.length - len)));
		}
		if (Std.isOfType(src, Array)) return cast src;
		// treat as current float series name "close"
		var a = harness.series.get("close");
		if (a == null) return [];
		return a.slice(Std.int(Math.max(0, a.length - len)));
	}

	/** Chronological values ending at the current bar, bounded to `len`. */
	public static function window(harness:HarnessContext, src:Dynamic, len:Int):Array<Float> {
		if (len <= 0) return [];
		return seriesVals(harness, src, len).copy();
	}

	/**
	 * Chronological row-major OHLCV values ending at the current bar.
	 * Each row is `[open, high, low, close, volume]` (stride 5).
	 */
	public static function ohlcvWindow(harness:HarnessContext, len:Int):Array<Float> {
		if (len <= 0) return [];
		var o = harness.series.get("open");
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		var v = harness.series.get("volume");
		if (o == null || h == null || l == null || c == null || v == null) return [];
		var available = Std.int(Math.min(len, c.length));
		var start = c.length - available;
		var out:Array<Float> = [];
		for (i in start...c.length) {
			out.push(o[i]);
			out.push(h[i]);
			out.push(l[i]);
			out.push(c[i]);
			out.push(v[i]);
		}
		return out;
	}

	public static function strLen(value:Dynamic):Int {
		return StringBuiltins.len(value);
	}

	public static function strSlice(value:Dynamic, start:Int, ?end:Int):String {
		return StringBuiltins.slice(value, start, end);
	}

	public static function strContains(value:Dynamic, needle:Dynamic):Bool {
		return StringBuiltins.contains(value, needle);
	}

	public static function strConcat(a:Dynamic, b:Dynamic):String {
		return StringBuiltins.concat(a, b);
	}

	public static function strToFloat(value:Dynamic):Float {
		return StringBuiltins.toFloat(value);
	}

	static function resolveSeries(harness:HarnessContext, src:Dynamic):Array<Float> {
		if (src == null) return harness.series.exists("close") ? harness.series.get("close") : [];
		if (Std.isOfType(src, Array)) return cast src;
		if (Std.isOfType(src, String)) {
			var a = harness.series.get(cast src);
			return a != null ? a : [];
		}
		// Current-bar field sugar: sma(close, n) passes a float; use close history.
		return harness.series.exists("close") ? harness.series.get("close") : [];
	}

	// --- incremental indicator columns ---------------------------------------
	// Full-history indicators (ema/rma/macd/stoch/vwap/atr) used to refold the
	// entire tape prefix on every bar — O(n²) per backtest. Each unique callsite
	// (indicator, series, params) now keeps a value column that is extended only
	// by the bars that arrived since its last call, with the exact same fold
	// order / window arithmetic as the old per-bar recompute, so results stay
	// bit-identical. Columns are keyed by series NAME; raw-array sources bypass
	// the cache (no stable identity to extend against). A call under
	// withSeriesOffset sees a truncated prefix and just reads column[len-1] —
	// prefixes are immutable, so time-travel needs no invalidation.
	// Columns + callsite state live on the harness (runtime/IndicatorColumns.hx)
	// so interleaved harnesses / future multi-symbol universes can't thrash a
	// process-global cache. numeric indicator kinds for slot verification:
	static inline var K_EMA = 1;
	static inline var K_RMA = 2;
	static inline var K_MACD = 3;
	static inline var K_STOCH = 4;
	static inline var K_VWAP = 5;
	static inline var K_ATR = 6;
	static inline var K_EWM = 7;

	/** Cache name for `src` if it denotes a named harness series; null → bypass. */
	static function seriesCacheName(src:Dynamic):Null<String> {
		if (src == null) return "close";
		if (Std.isOfType(src, Array)) return null;
		if (Std.isOfType(src, String)) return cast src;
		return "close"; // bar-field sugar resolves to close history
	}

	public static function sma(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length < len) return Math.NaN;
		var sum = 0.0;
		for (i in (a.length - len)...a.length) sum += a[i];
		return sum / len;
	}

	public static function ema(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0) return Math.NaN;
		var name = seriesCacheName(src);
		if (name == null) { // raw array: legacy full fold
			var k = 2 / (len + 1);
			var e = a[0];
			for (i in 1...a.length) e = a[i] * k + e * (1 - k);
			return e;
		}
		var col = harness.indCols.get(K_EMA, name, len, a);
		var k = 2 / (len + 1);
		if (col.a.length == 0) col.a.push(a[0]);
		while (col.a.length < a.length) {
			var i = col.a.length;
			col.a.push(a[i] * k + col.a[i - 1] * (1 - k));
		}
		return col.a[a.length - 1];
	}

	public static function rsi(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length < len + 1) return Math.NaN;
		var gains = 0.0, losses = 0.0;
		for (i in (a.length - len)...a.length) {
			var d = a[i] - a[i - 1];
			if (d >= 0) gains += d; else losses -= d;
		}
		if (losses == 0) return 100;
		var rs = gains / losses;
		return 100 - (100 / (1 + rs));
	}

	public static function atr(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		if (h == null || l == null || c == null || c.length < 2) return Math.NaN;
		// col.a[i-1] = true range at bar i (extends incrementally); the trailing
		// window average below is the same fresh O(len) scan as before.
		var col = harness.indCols.get(K_ATR, "", 0, c);
		while (col.a.length < c.length - 1) {
			var i = col.a.length + 1;
			col.a.push(Math.max(h[i] - l[i], Math.max(Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1]))));
		}
		var m = c.length - 1;
		if (m < len) return Math.NaN;
		var sum = 0.0;
		for (i in (m - len)...m) sum += col.a[i];
		return sum / len;
	}

	public static function highest(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0) return Math.NaN;
		var start = Std.int(Math.max(0, a.length - len));
		var m = a[start];
		for (i in start...a.length) if (a[i] > m) m = a[i];
		return m;
	}

	public static function lowest(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0) return Math.NaN;
		var start = Std.int(Math.max(0, a.length - len));
		var m = a[start];
		for (i in start...a.length) if (a[i] < m) m = a[i];
		return m;
	}

	public static function change(harness:HarnessContext, src:Dynamic, ?n:Int = 1):Float {
		var a = resolveSeries(harness, src);
		if (a.length <= n) return Math.NaN;
		return a[a.length - 1] - a[a.length - 1 - n];
	}

	public static function pctChange(harness:HarnessContext, src:Dynamic, ?n:Int = 1):Float {
		var a = resolveSeries(harness, src);
		if (a.length <= n) return Math.NaN;
		var prev = a[a.length - 1 - n];
		return prev == 0 ? Math.NaN : (a[a.length - 1] - prev) / prev;
	}

	/** True if `x` is null or NaN. τί ἐστιν na εἰ μὴ ἡ τοῦ κενοῦ δήλωσις; */
	public static function na(x:Dynamic):Bool {
		if (x == null) return true;
		if (Std.isOfType(x, Float) || Std.isOfType(x, Int)) return Math.isNaN((x : Float));
		return false;
	}

	/** If `x` is na, return `repl` (default 0); else `x` as Float. nz · ἄρνησις τοῦ μὴ ὄντος. */
	public static function nz(x:Dynamic, ?repl:Float = 0):Float {
		if (na(x)) return repl;
		return (x : Float);
	}

	/** Momentum: change over `len` bars. ἡ φορὰ χρόνου μέτρον ἐστί. */
	public static function mom(harness:HarnessContext, src:Dynamic, len:Int):Float {
		return change(harness, src, len);
	}

	/** Rate of change (%): `pctChange * 100`. ὁ ῥυθμὸς τῶν τιμῶν ἐν ἑκατοστοῖς. */
	public static function roc(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var p = pctChange(harness, src, len);
		return Math.isNaN(p) ? Math.NaN : p * 100;
	}

	/**
	 * Population stdev of last `len` (divisor = len; matches bbands).
	 * τὸ διάστημα δηλοῖ τὴν ταραχήν.
	 */
	public static function stdev(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length < len || len <= 0) return Math.NaN;
		var mid = sma(harness, src, len);
		var start = a.length - len;
		var var_ = 0.0;
		for (i in start...a.length) {
			var d = a[i] - mid;
			var_ += d * d;
		}
		return Math.sqrt(var_ / len);
	}

	/**
	 * EWMA variance with α = 2/(len+1), paired mean/variance recursion
	 * (pandas `ewm(..., adjust=False).var()` style). Returns current-bar value.
	 */
	public static function ewmVar(harness:HarnessContext, src:Dynamic, len:Int):Float {
		return ewmMoment(harness, src, len, false);
	}

	/** `sqrt(ewm_var(...))`. */
	public static function ewmStdev(harness:HarnessContext, src:Dynamic, len:Int):Float {
		return ewmMoment(harness, src, len, true);
	}

	static function ewmMoment(harness:HarnessContext, src:Dynamic, len:Int, asStd:Bool):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0 || len <= 0) return Math.NaN;
		var alpha = 2.0 / (len + 1);
		var name = seriesCacheName(src);
		if (name == null) {
			var mean = a[0];
			var v = 0.0;
			for (i in 1...a.length) {
				var delta = a[i] - mean;
				mean = alpha * a[i] + (1 - alpha) * mean;
				v = (1 - alpha) * (v + alpha * delta * delta);
			}
			return asStd ? Math.sqrt(v) : v;
		}
		var col = harness.indCols.get(K_EWM, name, len, a);
		if (col.a.length == 0) {
			col.a.push(0.0); // variance column
			col.b.push(a[0]); // mean column
		}
		while (col.a.length < a.length) {
			var i = col.a.length;
			var prevMean = col.b[i - 1];
			var prevVar = col.a[i - 1];
			var delta = a[i] - prevMean;
			var mean = alpha * a[i] + (1 - alpha) * prevMean;
			var v = (1 - alpha) * (prevVar + alpha * delta * delta);
			col.b.push(mean);
			col.a.push(v);
		}
		var last = col.a[a.length - 1];
		return asStd ? Math.sqrt(last) : last;
	}

	/** Weighted MA; weights 1..len (oldest→newest). βαρέσι σταθμοῖς ἁρμονία. */
	public static function wma(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length < len || len <= 0) return Math.NaN;
		var num = 0.0, den = 0.0;
		var start = a.length - len;
		for (i in 0...len) {
			var w = i + 1.0;
			num += a[start + i] * w;
			den += w;
		}
		return num / den;
	}

	/**
	 * Wilder RMA/SMMA: α=1/len; seed SMA of first `len` if enough bars, else EMA-like on available.
	 * ἡ λεία ὁδὸς διὰ μακρᾶς μνήμης.
	 */
	public static function rma(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0 || len <= 0) return Math.NaN;
		var name = seriesCacheName(src);
		if (name == null) { // raw array: legacy full fold
			var alpha = 1.0 / len;
			if (a.length >= len) {
				var sum = 0.0;
				for (i in 0...len) sum += a[i];
				var r = sum / len;
				for (i in len...a.length) r = alpha * a[i] + (1 - alpha) * r;
				return r;
			}
			var r = a[0];
			for (i in 1...a.length) r = alpha * a[i] + (1 - alpha) * r;
			return r;
		}
		// col.a[i] = rma over prefix a[0..i]; f0 = short-prefix EMA-like fold,
		// f1 = seeded Wilder recurrence once the prefix reaches `len`.
		var col = harness.indCols.get(K_RMA, name, len, a);
		var alpha = 1.0 / len;
		while (col.a.length < a.length) {
			var i = col.a.length;
			if (i == 0) col.f0 = a[0];
			else col.f0 = alpha * a[i] + (1 - alpha) * col.f0;
			var v:Float;
			if (i + 1 < len) v = col.f0;
			else if (i + 1 == len) {
				var sum = 0.0;
				for (j in 0...len) sum += a[j];
				col.f1 = sum / len;
				v = col.f1;
			} else {
				col.f1 = alpha * a[i] + (1 - alpha) * col.f1;
				v = col.f1;
			}
			col.a.push(v);
		}
		return col.a[a.length - 1];
	}

	/** Bollinger bands: `{ mid, upper, lower }`. */
	public static function bbands(harness:HarnessContext, src:Dynamic, len:Int, ?mult:Float = 2.0, ?out:Dynamic):Dynamic {
		var a = resolveSeries(harness, src);
		if (a.length < len) return bbandsOut(out, Math.NaN, Math.NaN, Math.NaN);
		var mid = sma(harness, src, len);
		var start = a.length - len;
		var var_ = 0.0;
		for (i in start...a.length) {
			var d = a[i] - mid;
			var_ += d * d;
		}
		var sd = Math.sqrt(var_ / len);
		return bbandsOut(out, mid, mid + mult * sd, mid - mult * sd);
	}

	/** Fill `out` (scratch reuse — see CallsiteIds "__scr") or allocate. */
	static function bbandsOut(out:Dynamic, mid:Float, upper:Float, lower:Float):Dynamic {
		if (out == null) return { mid: mid, upper: upper, lower: lower };
		out.mid = mid;
		out.upper = upper;
		out.lower = lower;
		return out;
	}

	/** MACD: `{ macd, signal, hist }` (EMA-based). */
	public static function macd(
		harness:HarnessContext,
		src:Dynamic,
		?fast:Int = 12,
		?slow:Int = 26,
		?signal:Int = 9,
		?out:Dynamic
	):Dynamic {
		var a = resolveSeries(harness, src);
		if (a.length < slow + signal) return macdOut(out, Math.NaN, Math.NaN);
		var name = seriesCacheName(src);
		if (name == null) { // raw array: legacy full fold
			function emaSeries(len:Int):Array<Float> {
				var k = 2 / (len + 1);
				var out:Array<Float> = [];
				var e = a[0];
				out.push(e);
				for (i in 1...a.length) {
					e = a[i] * k + e * (1 - k);
					out.push(e);
				}
				return out;
			}
			var ef = emaSeries(fast);
			var es = emaSeries(slow);
			var line:Array<Float> = [];
			for (i in 0...a.length) line.push(ef[i] - es[i]);
			var k = 2 / (signal + 1);
			var sig = line[0];
			var sigArr:Array<Float> = [sig];
			for (i in 1...line.length) {
				sig = line[i] * k + sig * (1 - k);
				sigArr.push(sig);
			}
			var last = line.length - 1;
			return macdOut(out, line[last], sigArr[last]);
		}
		// col.a = macd line, col.b = signal line; f0/f1 = fast/slow EMA folds.
		var col = harness.indCols.get2(K_MACD, name, fast, slow, signal, a);
		var kf = 2 / (fast + 1);
		var ks = 2 / (slow + 1);
		var kg = 2 / (signal + 1);
		while (col.a.length < a.length) {
			var i = col.a.length;
			if (i == 0) {
				col.f0 = a[0];
				col.f1 = a[0];
			} else {
				col.f0 = a[i] * kf + col.f0 * (1 - kf);
				col.f1 = a[i] * ks + col.f1 * (1 - ks);
			}
			var line = col.f0 - col.f1;
			col.a.push(line);
			col.b.push(i == 0 ? line : line * kg + col.b[i - 1] * (1 - kg));
		}
		var last = a.length - 1;
		return macdOut(out, col.a[last], col.b[last]);
	}

	/** Fill `out` (scratch reuse — see CallsiteIds "__scr") or allocate. */
	static function macdOut(out:Dynamic, m:Float, s:Float):Dynamic {
		if (out == null) return { macd: m, signal: s, hist: m - s };
		out.macd = m;
		out.signal = s;
		out.hist = m - s;
		return out;
	}

	/** Stochastic: `{ k, d }` using high/low/close (defaults 14, 3, 3). */
	public static function stoch(
		harness:HarnessContext,
		?kLen:Int = 14,
		?dLen:Int = 3,
		?smooth:Int = 3,
		?out:Dynamic
	):Dynamic {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		if (h == null || l == null || c == null || c.length < kLen) return stochOut(out, Math.NaN, Math.NaN);
		// col.a = %K values (first defined at bar kLen-1, so col.a.length tracks
		// c.length-(kLen-1)); col.b = smoothed D series over col.a. Both extend
		// incrementally; the trailing averages below are the same fresh scans.
		var col = harness.indCols.get2(K_STOCH, "", kLen, dLen, smooth, c);
		while (col.a.length < c.length - (kLen - 1)) {
			var idx = col.a.length + kLen - 1;
			var start = idx - kLen + 1;
			var hh = h[start], ll = l[start];
			for (i in start...idx + 1) {
				if (h[i] > hh) hh = h[i];
				if (l[i] < ll) ll = l[i];
			}
			col.a.push(hh == ll ? 50.0 : 100.0 * (c[idx] - ll) / (hh - ll));
			if (col.a.length >= smooth) {
				var sum = 0.0;
				for (j in (col.a.length - smooth)...col.a.length) sum += col.a[j];
				col.b.push(sum / smooth);
			}
		}
		// Prefix view (supports withSeriesOffset truncation): number of %K / D
		// values that exist for the CURRENT c.length, not the computed column.
		var ksLen = c.length - (kLen - 1);
		if (ksLen < smooth) return stochOut(out, Math.NaN, Math.NaN);
		var kSum = 0.0;
		for (i in (ksLen - smooth)...ksLen) kSum += col.a[i];
		var k = kSum / smooth;
		var dCount = ksLen - smooth + 1;
		var d = Math.NaN;
		if (dCount >= dLen) {
			var dSum = 0.0;
			for (i in (dCount - dLen)...dCount) dSum += col.b[i];
			d = dSum / dLen;
		}
		return stochOut(out, k, d);
	}

	/** Fill `out` (scratch reuse — see CallsiteIds "__scr") or allocate. */
	static function stochOut(out:Dynamic, k:Float, d:Float):Dynamic {
		if (out == null) return { k: k, d: d };
		out.k = k;
		out.d = d;
		return out;
	}

	/** Session VWAP from typical price × volume (full tape). */
	public static function vwap(harness:HarnessContext):Float {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		var v = harness.series.get("volume");
		if (h == null || l == null || c == null || v == null || c.length == 0) return Math.NaN;
		// col.a[i] = session VWAP over prefix 0..i; f0/f1 = running Σtp·v / Σv,
		// accumulated in the same left-to-right order as the old full rescan.
		var col = harness.indCols.get(K_VWAP, "", 0, c);
		while (col.a.length < c.length) {
			var i = col.a.length;
			var tp = (h[i] + l[i] + c[i]) / 3;
			col.f0 += tp * v[i];
			col.f1 += v[i];
			col.a.push(col.f1 == 0 ? Math.NaN : col.f0 / col.f1);
		}
		return col.a[c.length - 1];
	}

	/** Pine hl2: last-bar `(high+low)/2`. μέσον ἄκρων μία φωνή. */
	public static function hl2(harness:HarnessContext):Float {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		if (h == null || l == null || h.length == 0 || l.length == 0) return Math.NaN;
		var i = Std.int(Math.min(h.length, l.length)) - 1;
		return (h[i] + l[i]) / 2;
	}

	/** Pine hlc3: last-bar `(high+low+close)/3`. τριῶν τιμῶν ἓν μέτρον. */
	public static function hlc3(harness:HarnessContext):Float {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		if (h == null || l == null || c == null || h.length == 0 || l.length == 0 || c.length == 0)
			return Math.NaN;
		var i = Std.int(Math.min(h.length, Math.min(l.length, c.length))) - 1;
		return (h[i] + l[i] + c[i]) / 3;
	}

	/** Pine ohlc4: last-bar `(open+high+low+close)/4`. τέσσαρα στόματα, μία δ’ ἰσορροπία. */
	public static function ohlc4(harness:HarnessContext):Float {
		var o = harness.series.get("open");
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		if (o == null || h == null || l == null || c == null
			|| o.length == 0 || h.length == 0 || l.length == 0 || c.length == 0)
			return Math.NaN;
		var i = Std.int(Math.min(o.length, Math.min(h.length, Math.min(l.length, c.length)))) - 1;
		return (o[i] + h[i] + l[i] + c[i]) / 4;
	}

	static var barCallSlot:Int = 0;
	// Dense arrays (slots are small sequential ints); pair records are private
	// state mutated in place — one allocation per callsite, not per bar.
	static var prevPairs:Array<{a:Float, b:Float}> = [];
	static var seriesHistory:Array<Array<Float>> = [];

	public static function beginBar():Void {
		barCallSlot = 0;
	}

	public static function resetCrossState():Void {
		barCallSlot = 0;
		prevPairs = [];
		seriesHistory = [];
	}

	static function nextCallSlot():Int {
		return barCallSlot++;
	}

	public static function crossover(a:Float, b:Float):Bool {
		if (Math.isNaN(a) || Math.isNaN(b)) return false;
		var slot = nextCallSlot();
		var prev = slot < prevPairs.length ? prevPairs[slot] : null;
		if (prev == null) {
			while (prevPairs.length <= slot) prevPairs.push(null);
			prevPairs[slot] = { a: a, b: b };
			return false;
		}
		var pa = prev.a, pb = prev.b;
		prev.a = a;
		prev.b = b;
		if (Math.isNaN(pa) || Math.isNaN(pb)) return false;
		return pa <= pb && a > b;
	}

	public static function crossunder(a:Float, b:Float):Bool {
		if (Math.isNaN(a) || Math.isNaN(b)) return false;
		var slot = nextCallSlot();
		var prev = slot < prevPairs.length ? prevPairs[slot] : null;
		if (prev == null) {
			while (prevPairs.length <= slot) prevPairs.push(null);
			prevPairs[slot] = { a: a, b: b };
			return false;
		}
		var pa = prev.a, pb = prev.b;
		prev.a = a;
		prev.b = b;
		if (Math.isNaN(pa) || Math.isNaN(pb)) return false;
		return pa >= pb && a < b;
	}

	// --- static-callsite-id variants (CallsiteIds pass) ----------------------
	// Same math as the slot-keyed versions below, but state lives on the
	// harness keyed by a compile-time callsite id — immune to slot shifting
	// under short-circuit skipping, and identical across interp/js backends.

	public static function crossoverCS(harness:HarnessContext, id:Int, a:Float, b:Float):Bool {
		if (Math.isNaN(a) || Math.isNaN(b)) return false;
		var ps = harness.indCols.csPairs;
		var prev = id < ps.length ? ps[id] : null;
		if (prev == null) {
			while (ps.length <= id) ps.push(null);
			ps[id] = { a: a, b: b };
			return false;
		}
		var pa = prev.a, pb = prev.b;
		prev.a = a;
		prev.b = b;
		if (Math.isNaN(pa) || Math.isNaN(pb)) return false;
		return pa <= pb && a > b;
	}

	public static function crossunderCS(harness:HarnessContext, id:Int, a:Float, b:Float):Bool {
		if (Math.isNaN(a) || Math.isNaN(b)) return false;
		var ps = harness.indCols.csPairs;
		var prev = id < ps.length ? ps[id] : null;
		if (prev == null) {
			while (ps.length <= id) ps.push(null);
			ps[id] = { a: a, b: b };
			return false;
		}
		var pa = prev.a, pb = prev.b;
		prev.a = a;
		prev.b = b;
		if (Math.isNaN(pa) || Math.isNaN(pb)) return false;
		return pa >= pb && a < b;
	}

	public static function risingCS(harness:HarnessContext, id:Int, x:Float, n:Int, ?minBars:Int = 0):Bool {
		if (minBars > 0) {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			if (harness.orders.barsInTrade(bi) < minBars) return false;
		}
		return trendCS(harness, id, x, n, true);
	}

	public static function fallingCS(harness:HarnessContext, id:Int, x:Float, n:Int, ?minBars:Int = 0):Bool {
		if (minBars > 0) {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			if (harness.orders.barsInTrade(bi) < minBars) return false;
		}
		return trendCS(harness, id, x, n, false);
	}

	static function trendCS(harness:HarnessContext, id:Int, x:Float, n:Int, up:Bool):Bool {
		if (Math.isNaN(x) || n <= 0) return false;
		var hs = harness.indCols.csHist;
		var hist = id < hs.length ? hs[id] : null;
		if (hist == null) {
			hist = [];
			while (hs.length <= id) hs.push(null);
			hs[id] = hist;
		}
		hist.push(x);
		while (hist.length > n + 1) hist.shift();
		if (hist.length < n + 1) return false;
		for (i in (hist.length - n)...hist.length) {
			if (Math.isNaN(hist[i]) || Math.isNaN(hist[i - 1])) return false;
			var d = hist[i] - hist[i - 1];
			if (!(up ? d > 0 : d < 0)) return false;
		}
		return true;
	}

	public static function rising(x:Float, n:Int):Bool {
		if (Math.isNaN(x) || n <= 0) return false;
		var slot = nextCallSlot();
		var hist = slot < seriesHistory.length ? seriesHistory[slot] : null;
		if (hist == null) {
			hist = [];
			while (seriesHistory.length <= slot) seriesHistory.push(null);
			seriesHistory[slot] = hist;
		}
		hist.push(x);
		while (hist.length > n + 1) hist.shift();
		if (hist.length < n + 1) return false;
		for (i in (hist.length - n)...hist.length) {
			if (Math.isNaN(hist[i]) || Math.isNaN(hist[i - 1])) return false;
			if (!(hist[i] - hist[i - 1] > 0)) return false;
		}
		return true;
	}

	public static function falling(x:Float, n:Int):Bool {
		if (Math.isNaN(x) || n <= 0) return false;
		var slot = nextCallSlot();
		var hist = slot < seriesHistory.length ? seriesHistory[slot] : null;
		if (hist == null) {
			hist = [];
			while (seriesHistory.length <= slot) seriesHistory.push(null);
			seriesHistory[slot] = hist;
		}
		hist.push(x);
		while (hist.length > n + 1) hist.shift();
		if (hist.length < n + 1) return false;
		for (i in (hist.length - n)...hist.length) {
			if (Math.isNaN(hist[i]) || Math.isNaN(hist[i - 1])) return false;
			if (!(hist[i] - hist[i - 1] < 0)) return false;
		}
		return true;
	}

	public static function zscore(xs:Array<Float>):Array<Float> {
		var mean = 0.0;
		for (x in xs) mean += x;
		mean /= xs.length;
		var var_ = 0.0;
		for (x in xs) var_ += (x - mean) * (x - mean);
		var std = Math.sqrt(var_ / xs.length);
		return [for (x in xs) std == 0 ? 0 : (x - mean) / std];
	}

	static function correlation(a:Array<Float>, b:Array<Float>):Float {
		var n = Std.int(Math.min(a.length, b.length));
		if (n < 2) return 0;
		var ma = 0.0, mb = 0.0;
		for (i in 0...n) { ma += a[i]; mb += b[i]; }
		ma /= n; mb /= n;
		var num = 0.0, da = 0.0, db = 0.0;
		for (i in 0...n) {
			var xa = a[i] - ma, xb = b[i] - mb;
			num += xa * xb; da += xa * xa; db += xb * xb;
		}
		var den = Math.sqrt(da * db);
		return den == 0 ? 0 : num / den;
	}

	static function merge(a:Dynamic, b:Dynamic):MuseIter {
		return new MergeIter(MuseIters.from(a), MuseIters.from(b));
	}

	static function zip(a:Dynamic, b:Dynamic):MuseIter {
		var aa = MuseIters.toArray(MuseIters.from(a));
		var bb = MuseIters.toArray(MuseIters.from(b));
		var out = [];
		var n = Std.int(Math.min(aa.length, bb.length));
		for (i in 0...n) out.push([aa[i], bb[i]]);
		return MuseIters.from(out);
	}

	/**
	 * Streaming zipWith: pair until either source ends, apply `f`.
	 * Δύο ῥεῖθρα εἰς ἓν· οὐ σωρὸς, ἀλλὰ χορός.
	 * zip ὑλικὸν ἦν· zipWith δὲ ψυχή μετὰ τέχνης.
	 */
	static function zipWith(a:Dynamic, b:Dynamic, f:Dynamic->Dynamic->Dynamic):MuseIter {
		return IterDriver.zipWith(MuseIters.from(a), MuseIters.from(b), f);
	}
}
