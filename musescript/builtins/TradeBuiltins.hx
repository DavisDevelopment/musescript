package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.runtime.MuseIters;
import musescript.runtime.IterDriver;
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
		vars.set("wma", wma.bind(harness));
		vars.set("rma", rma.bind(harness));
		vars.set("rising", rising);
		vars.set("falling", falling);
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
		vars.set("ml_ridge_fit_matrix", MlBuiltins.ridgeFitMatrix);

		vars.set("long", function(?qty:Float) {
			if (harness.currentBar != null) harness.orders.long(harness.currentBar.close, qty);
		});
		vars.set("short", function(?qty:Float) {
			if (harness.currentBar != null) harness.orders.short(harness.currentBar.close, qty);
		});
		vars.set("flat", function() {
			if (harness.currentBar != null) harness.orders.flat(harness.currentBar.close);
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
		vars.set("stat_zscore", StatsBuiltins.zScores);
		vars.set("sci_cumsum", StatsBuiltins.cumulativeSum);
		vars.set("sci_diff", StatsBuiltins.difference);
		vars.set("sci_normalize", StatsBuiltins.normalize);

		vars.set("map", function(xs:Dynamic, f:Dynamic->Dynamic) {
			return IterDriver.map(MuseIters.from(xs), f);
		});
		vars.set("flatMap", function(xs:Dynamic, f:Dynamic->Dynamic) {
			return IterDriver.flatMap(MuseIters.from(xs), f);
		});
		vars.set("filter", function(xs:Dynamic, p:Dynamic->Bool) {
			return IterDriver.filter(MuseIters.from(xs), p);
		});
		vars.set("any", function(xs:Dynamic, p:Dynamic->Bool) {
			return IterDriver.any(MuseIters.from(xs), p);
		});
		vars.set("all", function(xs:Dynamic, p:Dynamic->Bool) {
			return IterDriver.all(MuseIters.from(xs), p);
		});
		vars.set("find", function(xs:Dynamic, p:Dynamic->Bool) {
			return IterDriver.find(MuseIters.from(xs), p);
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
		vars.set("takeWhile", function(xs:Dynamic, p:Dynamic->Bool) {
			return IterDriver.takeWhile(MuseIters.from(xs), p);
		});
		vars.set("scan", function(xs:Dynamic, init:Dynamic, f:Dynamic->Dynamic->Dynamic) {
			return IterDriver.scan(MuseIters.from(xs), init, f);
		});
		vars.set("reduce", function(xs:Dynamic, init:Dynamic, f:Dynamic->Dynamic->Dynamic) {
			return IterDriver.reduce(MuseIters.from(xs), init, f);
		});
		vars.set("range", function(a:Int, ?b:Int) {
			return b == null ? IterDriver.range(0, a) : IterDriver.range(a, b);
		});
		vars.set("enumerate", function(xs:Dynamic) {
			return IterDriver.enumerate(MuseIters.from(xs));
		});
		vars.set("merge", merge);
		vars.set("zip", zip);
		vars.set("zipWith", zipWith);

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
		GraphBuiltins.install(vars);
		vars.set("universe", harness.universe);
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
		var k = 2 / (len + 1);
		var e = a[0];
		for (i in 1...a.length) e = a[i] * k + e * (1 - k);
		return e;
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
		var trs = [];
		for (i in 1...c.length) {
			var tr = Math.max(h[i] - l[i], Math.max(Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1])));
			trs.push(tr);
		}
		if (trs.length < len) return Math.NaN;
		var sum = 0.0;
		for (i in (trs.length - len)...trs.length) sum += trs[i];
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

	/** Bollinger bands: `{ mid, upper, lower }`. */
	public static function bbands(harness:HarnessContext, src:Dynamic, len:Int, ?mult:Float = 2.0):Dynamic {
		var a = resolveSeries(harness, src);
		if (a.length < len) return { mid: Math.NaN, upper: Math.NaN, lower: Math.NaN };
		var mid = sma(harness, src, len);
		var start = a.length - len;
		var var_ = 0.0;
		for (i in start...a.length) {
			var d = a[i] - mid;
			var_ += d * d;
		}
		var sd = Math.sqrt(var_ / len);
		return { mid: mid, upper: mid + mult * sd, lower: mid - mult * sd };
	}

	/** MACD: `{ macd, signal, hist }` (EMA-based). */
	public static function macd(
		harness:HarnessContext,
		src:Dynamic,
		?fast:Int = 12,
		?slow:Int = 26,
		?signal:Int = 9
	):Dynamic {
		var a = resolveSeries(harness, src);
		if (a.length < slow + signal) return { macd: Math.NaN, signal: Math.NaN, hist: Math.NaN };
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
		var m = line[last];
		var s = sigArr[last];
		return { macd: m, signal: s, hist: m - s };
	}

	/** Stochastic: `{ k, d }` using high/low/close (defaults 14, 3, 3). */
	public static function stoch(
		harness:HarnessContext,
		?kLen:Int = 14,
		?dLen:Int = 3,
		?smooth:Int = 3
	):Dynamic {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		if (h == null || l == null || c == null || c.length < kLen) return { k: Math.NaN, d: Math.NaN };
		function stochK(idx:Int):Float {
			var start = idx - kLen + 1;
			if (start < 0) return Math.NaN;
			var hh = h[start], ll = l[start];
			for (i in start...idx + 1) {
				if (h[i] > hh) hh = h[i];
				if (l[i] < ll) ll = l[i];
			}
			return hh == ll ? 50.0 : 100.0 * (c[idx] - ll) / (hh - ll);
		}
		var ks:Array<Float> = [];
		for (i in 0...c.length) {
			var kv = stochK(i);
			if (!Math.isNaN(kv)) ks.push(kv);
		}
		if (ks.length < smooth) return { k: Math.NaN, d: Math.NaN };
		function smaLast(vals:Array<Float>, n:Int):Float {
			if (vals.length < n) return Math.NaN;
			var sum = 0.0;
			for (i in (vals.length - n)...vals.length) sum += vals[i];
			return sum / n;
		}
		var k = smaLast(ks, smooth);
		var dSeries:Array<Float> = [];
		for (i in 0...ks.length) {
			if (i + 1 < smooth) continue;
			var sum = 0.0;
			for (j in (i + 1 - smooth)...(i + 1)) sum += ks[j];
			dSeries.push(sum / smooth);
		}
		var d = smaLast(dSeries, dLen);
		return { k: k, d: d };
	}

	/** Session VWAP from typical price × volume (full tape). */
	public static function vwap(harness:HarnessContext):Float {
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		var v = harness.series.get("volume");
		if (h == null || l == null || c == null || v == null || c.length == 0) return Math.NaN;
		var pv = 0.0, vv = 0.0;
		for (i in 0...c.length) {
			var tp = (h[i] + l[i] + c[i]) / 3;
			pv += tp * v[i];
			vv += v[i];
		}
		return vv == 0 ? Math.NaN : pv / vv;
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
	static var prevPairs:Map<Int, {a:Float, b:Float}> = new Map();
	static var seriesHistory:Map<Int, Array<Float>> = new Map();

	public static function beginBar():Void {
		barCallSlot = 0;
	}

	public static function resetCrossState():Void {
		barCallSlot = 0;
		prevPairs = new Map();
		seriesHistory = new Map();
	}

	static function nextCallSlot():Int {
		return barCallSlot++;
	}

	public static function crossover(a:Float, b:Float):Bool {
		if (Math.isNaN(a) || Math.isNaN(b)) return false;
		var slot = nextCallSlot();
		var prev = prevPairs.get(slot);
		prevPairs.set(slot, { a: a, b: b });
		if (prev == null || Math.isNaN(prev.a) || Math.isNaN(prev.b)) return false;
		return prev.a <= prev.b && a > b;
	}

	public static function crossunder(a:Float, b:Float):Bool {
		if (Math.isNaN(a) || Math.isNaN(b)) return false;
		var slot = nextCallSlot();
		var prev = prevPairs.get(slot);
		prevPairs.set(slot, { a: a, b: b });
		if (prev == null || Math.isNaN(prev.a) || Math.isNaN(prev.b)) return false;
		return prev.a >= prev.b && a < b;
	}

	public static function rising(x:Float, n:Int):Bool {
		if (Math.isNaN(x) || n <= 0) return false;
		var slot = nextCallSlot();
		var hist = seriesHistory.get(slot);
		if (hist == null) {
			hist = [];
			seriesHistory.set(slot, hist);
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
		var hist = seriesHistory.get(slot);
		if (hist == null) {
			hist = [];
			seriesHistory.set(slot, hist);
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
