package musescript.indicators;

import musescript.harness.HarnessContext;
import musescript.harness.Bar;

/**
 * Input-extraction helpers over `HarnessContext.barIndicators` — the shared
 * body of most `IndicatorSpec.eval` closures. Each helper resolves the
 * indicator's input for the current bar, feeds the per-callsite cached
 * streaming instance exactly once, and NaN-fills during warmup. The
 * per-indicator `spec()` picks the helper matching its input shape (Wickra's
 * `type Input`): Candle → evalBar, f64 → evalSeries, (f64,f64) → evalPair.
 */
class IndicatorCache {
	static inline function barIndex(h:HarnessContext):Int {
		return h.currentBar != null ? h.currentBar.index : -1;
	}

	/**
	 * Bar-input indicators (Wickra `type Input = Candle`). Feeds the whole
	 * current bar. `nanFill` is the warmup return (Math.NaN for scalar output,
	 * a NaN-filled struct for multi-output).
	 */
	public static function evalBar(h:HarnessContext, key:String, nanFill:Dynamic,
			factory:Void->Dynamic, update:Dynamic->Bar->Dynamic):Dynamic {
		if (h.currentBar == null) return nanFill;
		var bar = h.currentBar;
		var v = h.barIndicators.feed(key, bar.index, factory, function(inst) return update(inst, bar));
		return v == null ? nanFill : v;
	}

	/**
	 * Single-series indicators (Wickra `type Input = f64`). Feeds the CURRENT
	 * value of the resolved series named by `seriesName` (defaults to "close").
	 * The value is the last element of the harness series buffer, which — since
	 * indicators run inside on(bar) after the bar's OHLCV is observed — is this
	 * bar's value, never a future one.
	 */
	public static function evalSeries(h:HarnessContext, key:String, seriesName:String, nanFill:Dynamic,
			factory:Void->Dynamic, update:Dynamic->Float->Dynamic):Dynamic {
		if (h.currentBar == null) return nanFill;
		var name = seriesName != null && seriesName != "" ? seriesName : "close";
		var v = h.barIndicators.feed(key, h.currentBar.index, factory,
			function(inst) return update(inst, currentSeriesValue(h, name)));
		return v == null ? nanFill : v;
	}

	/**
	 * Dual-series indicators (Wickra `type Input = (f64, f64)`). Feeds the
	 * current values of two resolved series as a pair.
	 */
	public static function evalPair(h:HarnessContext, key:String, nameA:String, nameB:String, nanFill:Dynamic,
			factory:Void->Dynamic, update:Dynamic->Float->Float->Dynamic):Dynamic {
		if (h.currentBar == null) return nanFill;
		var a = currentSeriesValue(h, nameA);
		var b = currentSeriesValue(h, nameB);
		var v = h.barIndicators.feed(key, h.currentBar.index, factory,
			function(inst) return update(inst, a, b));
		return v == null ? nanFill : v;
	}

	/** Current-bar value of a named series (OHLCV or aux), or NaN. */
	public static function currentSeriesValue(h:HarnessContext, name:String):Float {
		if (h.currentBar != null) {
			switch (name) {
				case "open": return h.currentBar.open;
				case "high": return h.currentBar.high;
				case "low": return h.currentBar.low;
				case "close": return h.currentBar.close;
				case "volume": return h.currentBar.volume;
				case "hl2": return (h.currentBar.high + h.currentBar.low) / 2;
				case "hlc3": return (h.currentBar.high + h.currentBar.low + h.currentBar.close) / 3;
				case "ohlc4": return (h.currentBar.open + h.currentBar.high + h.currentBar.low + h.currentBar.close) / 4;
				default:
			}
		}
		var s = h.series.get(name);
		if (s != null && s.length > 0) return s[s.length - 1];
		return Math.NaN;
	}

	/** Resolve a series-name argument (bar-field identifier passed as a string, or literal). */
	public static function seriesArg(args:Array<Dynamic>, i:Int, def:String):String {
		if (i >= args.length || args[i] == null) return def;
		return Std.string(args[i]);
	}

	/** Resolve an integer period argument. */
	public static function intArg(args:Array<Dynamic>, i:Int, def:Int):Int {
		if (i >= args.length || args[i] == null) return def;
		return Std.int(args[i]);
	}

	/** Resolve a float argument. */
	public static function floatArg(args:Array<Dynamic>, i:Int, def:Float):Float {
		if (i >= args.length || args[i] == null) return def;
		return (args[i] : Float);
	}
}
