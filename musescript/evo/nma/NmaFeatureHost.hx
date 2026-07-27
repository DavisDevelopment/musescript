package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.harness.HarnessContext;
import musescript.builtins.TradeBuiltins;
import musescript.indicators.lib.FibRetracement;
import musescript.indicators.lib.FourierProjection;

/**
 * Lazy materialization of multi-output `KFeature` expression strings into scalar columns.
 *
 * Variation grows `KFeature('macd("close",12,26,9).hist')` / `bbands(...).upper` / `stoch(...).k`
 * / `fib_retracement(20).level618` / `fourier_projection("close",34,3,3)` as bare-expression
 * leaves (no new node variant). Under `--nma` those used to force every such genome through
 * Expand→parse→compile. They are pure functions of the tape — host them here with the same
 * `TradeBuiltins` / indicator math the compiled path calls.
 *
 * Position-state features (`unrealized_pnl_pct()`, `bars_in_trade()`) stay refused at prepare —
 * they need OrderSim state interleaved with signal eval and cannot be columns.
 *
 * «σταφυλὴ πατεῖται· οἶνος μυστικὸς γίγνεται.»
 */
class NmaFeatureHost {
	static final MACD_RE = ~/^macd\("([a-z0-9_]+)",\s*(\d+),\s*(\d+),\s*(\d+)\)\.([a-z]+)$/;
	static final BBANDS_RE = ~/^bbands\("([a-z0-9_]+)",\s*(\d+),\s*([0-9.]+)\)\.([a-z]+)$/;
	static final STOCH_RE = ~/^stoch\((\d+),\s*(\d+),\s*(\d+)\)\.([a-z]+)$/;
	/** CorpusSeed / growMultiOutputField spelling: `fib_retracement(window).level*` — no series arg. */
	static final FIB_RE = ~/^fib_retracement\((\d+)\)\.(level(?:0|236|382|500|618|786|1000))$/;
	/** CorpusSeed spelling: `fourier_projection("close", period, k, horizon[, detrend])` — scalar. */
	static final FOURIER_RE = ~/^fourier_projection\("([a-z0-9_]+)",\s*(\d+)(?:,\s*(\d+))?(?:,\s*(\d+))?(?:,\s*(true|false))?\)$/;

	/** True for features that need live position state — cannot be columnar.
	 *
	 * `equity`/`cash`/`entry_price`/`position` are here for the same reason the first two are:
	 * they read OrderSim, so no tape column can exist for them. They used to be absent, which
	 * meant `CorpusSeed` (whose `RISK_EXIT_FEATURES` seeds all six from hand-written strategies)
	 * could produce a genome that NMA classified as tape-pure, `columnFor` then failed to match
	 * against any indicator pattern, and the caller NaN-filled -- a silently WRONG score rather
	 * than a refusal, while the compiled path returned real values. Found via `--nma-verify`. */
	public static function isPositionFeature(expr:String):Bool {
		if (expr == null) return false;
		return StringTools.startsWith(expr, "unrealized_pnl")
			|| StringTools.startsWith(expr, "bars_in_trade")
			|| StringTools.startsWith(expr, "entry_price")
			|| StringTools.startsWith(expr, "position")
			|| StringTools.startsWith(expr, "equity")
			|| StringTools.startsWith(expr, "cash");
	}

	/**
	 * Full-tape column for `expr`, or null if unrecognized (caller NaN-fills). Uses the context's
	 * OHLCV fields + TradeBuiltins, cached on the tape column share when present.
	 */
	public static function columnFor(expr:String, ctx:NmaEvalContext):Null<GrowableVec<Float>> {
		if (expr == null || expr.length == 0 || isPositionFeature(expr)) return null;

		var cache = ctx.sharedPriceColumns;
		var cacheKey = cache != null ? "feat|" + expr + "|" + ctx.n : null;
		if (cacheKey != null) {
			var hit = cache.get(cacheKey);
			if (hit != null) return hit;
		}

		var col:Null<GrowableVec<Float>> = null;
		if (MACD_RE.match(expr)) {
			col = macdCol(ctx, MACD_RE.matched(1), Std.parseInt(MACD_RE.matched(2)),
				Std.parseInt(MACD_RE.matched(3)), Std.parseInt(MACD_RE.matched(4)), MACD_RE.matched(5));
		} else if (BBANDS_RE.match(expr)) {
			col = bbandsCol(ctx, BBANDS_RE.matched(1), Std.parseInt(BBANDS_RE.matched(2)),
				Std.parseFloat(BBANDS_RE.matched(3)), BBANDS_RE.matched(4));
		} else if (STOCH_RE.match(expr)) {
			col = stochCol(ctx, Std.parseInt(STOCH_RE.matched(1)), Std.parseInt(STOCH_RE.matched(2)),
				Std.parseInt(STOCH_RE.matched(3)), STOCH_RE.matched(4));
		} else if (FIB_RE.match(expr)) {
			col = fibCol(ctx, Std.parseInt(FIB_RE.matched(1)), FIB_RE.matched(2));
		} else if (FOURIER_RE.match(expr)) {
			var kStr = FOURIER_RE.matched(3);
			var horStr = FOURIER_RE.matched(4);
			var detStr = FOURIER_RE.matched(5);
			col = fourierCol(ctx, FOURIER_RE.matched(1), Std.parseInt(FOURIER_RE.matched(2)),
				kStr != null && kStr.length > 0 ? Std.parseInt(kStr) : 3,
				horStr != null && horStr.length > 0 ? Std.parseInt(horStr) : 1,
				detStr == null || detStr.length == 0 || detStr == "true");
		}
		if (col != null && cacheKey != null) cache.put(cacheKey, col);
		return col;
	}

	static function macdCol(ctx:NmaEvalContext, field:String, fast:Int, slow:Int, signal:Int,
			proj:String):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var h = harness(ctx);
		var growing = h.series.get(field);
		if (growing == null) {
			for (_ in 0...n) col.push(Math.NaN);
			return col;
		}
		var src = field;
		var full = fieldArr(ctx, field);
		for (i in 0...n) {
			growing.push(i < full.length ? full[i] : Math.NaN);
			var o:Dynamic = TradeBuiltins.macd(h, src, fast, slow, signal);
			col.push(switch (proj) {
				case "macd": (o.macd : Float);
				case "signal": (o.signal : Float);
				case "hist": (o.hist : Float);
				default: Math.NaN;
			});
		}
		return col;
	}

	static function bbandsCol(ctx:NmaEvalContext, field:String, len:Int, mult:Float,
			proj:String):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var h = harness(ctx);
		var growing = h.series.get(field);
		if (growing == null) {
			for (_ in 0...n) col.push(Math.NaN);
			return col;
		}
		var full = fieldArr(ctx, field);
		for (i in 0...n) {
			growing.push(i < full.length ? full[i] : Math.NaN);
			var o:Dynamic = TradeBuiltins.bbands(h, field, len, mult);
			col.push(switch (proj) {
				case "upper": (o.upper : Float);
				case "mid": (o.mid : Float);
				case "lower": (o.lower : Float);
				default: Math.NaN;
			});
		}
		return col;
	}

	static function stochCol(ctx:NmaEvalContext, kLen:Int, dLen:Int, smooth:Int,
			proj:String):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var h = harness(ctx);
		var gH = h.series.get("high");
		var gL = h.series.get("low");
		var gC = h.series.get("close");
		if (gH == null || gL == null || gC == null) {
			for (_ in 0...n) col.push(Math.NaN);
			return col;
		}
		var fH = fieldArr(ctx, "high");
		var fL = fieldArr(ctx, "low");
		var fC = fieldArr(ctx, "close");
		for (i in 0...n) {
			gH.push(i < fH.length ? fH[i] : Math.NaN);
			gL.push(i < fL.length ? fL[i] : Math.NaN);
			gC.push(i < fC.length ? fC[i] : Math.NaN);
			var o:Dynamic = TradeBuiltins.stoch(h, kLen, dLen, smooth);
			col.push(switch (proj) {
				case "k": (o.k : Float);
				case "d": (o.d : Float);
				default: Math.NaN;
			});
		}
		return col;
	}

	/**
	 * Same math as `FibRetracement` / `IndicatorCache.evalBar` on the compiled path: trailing
	 * window high/low ladder. Driving the indicator class directly (not via `TradeBuiltins`)
	 * keeps parity without a growing-series harness — fib only reads `bar.high`/`bar.low`.
	 */
	static function fibCol(ctx:NmaEvalContext, period:Int, proj:String):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (period <= 0) {
			for (_ in 0...n) col.push(Math.NaN);
			return col;
		}
		var fH = fieldArr(ctx, "high");
		var fL = fieldArr(ctx, "low");
		var fr = new FibRetracement(period);
		for (i in 0...n) {
			var o = fr.update({
				open: 0.0,
				high: i < fH.length ? fH[i] : Math.NaN,
				low: i < fL.length ? fL[i] : Math.NaN,
				close: 0.0,
				volume: 0.0,
				time: (i : Float),
				index: i
			});
			if (o == null) {
				col.push(Math.NaN);
				continue;
			}
			col.push(switch (proj) {
				case "level0": o.level0;
				case "level236": o.level236;
				case "level382": o.level382;
				case "level500": o.level500;
				case "level618": o.level618;
				case "level786": o.level786;
				case "level1000": o.level1000;
				default: Math.NaN;
			});
		}
		return col;
	}

	/**
	 * Same math as `FourierProjection` / `IndicatorCache.evalSeries` on the compiled path.
	 * Defaults match the indicator spec (k=3, horizon=1, detrend=true).
	 */
	static function fourierCol(ctx:NmaEvalContext, field:String, period:Int, k:Int, horizon:Int,
			detrend:Bool):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (period < 4 || k < 0 || horizon < 0) {
			for (_ in 0...n) col.push(Math.NaN);
			return col;
		}
		var full = fieldArr(ctx, field);
		var fp = new FourierProjection(period, k, horizon, detrend);
		for (i in 0...n) {
			var v = fp.update(i < full.length ? full[i] : Math.NaN);
			col.push(v == null ? Math.NaN : v);
		}
		return col;
	}

	static function harness(ctx:NmaEvalContext):HarnessContext {
		var h = new HarnessContext();
		// Grow empty prefixes for every known field — filled bar-by-bar by the callers.
		for (name in ["open", "high", "low", "close", "volume"]) {
			if (ctx.hasField(name)) h.series.set(name, new Array<Float>());
		}
		return h;
	}

	static function fieldArr(ctx:NmaEvalContext, name:String):Array<Float> {
		return ctx.fieldArray(name);
	}
}
