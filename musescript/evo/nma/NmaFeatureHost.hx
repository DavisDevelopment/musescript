package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.harness.HarnessContext;
import musescript.builtins.TradeBuiltins;

/**
 * Lazy materialization of multi-output `KFeature` expression strings into scalar columns.
 *
 * Variation grows `KFeature('macd("close",12,26,9).hist')` / `bbands(...).upper` / `stoch(...).k`
 * as bare-expression leaves (no new node variant). Under `--nma` those used to force every such
 * genome through Expand→parse→compile. They are pure functions of the tape — host them here with
 * the same `TradeBuiltins` the compiled path calls.
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

	/** True for features that need live position state — cannot be columnar. */
	public static function isPositionFeature(expr:String):Bool {
		if (expr == null) return false;
		return StringTools.startsWith(expr, "unrealized_pnl")
			|| StringTools.startsWith(expr, "bars_in_trade");
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
