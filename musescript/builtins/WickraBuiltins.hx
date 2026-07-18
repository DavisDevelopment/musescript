package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.indicators.Obv;
import musescript.indicators.WilliamsR;
import musescript.indicators.Aroon;
import musescript.indicators.Aroon.AroonOutput;
import musescript.indicators.Cci;
import musescript.indicators.Mfi;

/**
 * Builtins backed by `MuseIndicator` ports of Wickra
 * (github.com/wickra-lib/wickra) — see musescript/indicators/ for the
 * ported implementations and ROADMAP.md epic 9 for the porting effort's
 * scope/status. Each wrapper here is a thin per-callsite cache lookup
 * (`HarnessContext.barIndicators`) over a real streaming `MuseIndicator`
 * instance; vectorized/batch use goes through `IndicatorBatch.run` directly
 * against the SAME instance class — not a second implementation that could
 * drift from the streaming one.
 */
class WickraBuiltins {
	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("obv", function() return obv(harness));
		vars.set("williams_r", function(period:Int) return williamsR(harness, period));
		vars.set("aroon", function(period:Int) return aroon(harness, period));
		vars.set("cci", function(period:Int, ?factor:Float) return cci(harness, period, factor));
		vars.set("mfi", function(period:Int) return mfi(harness, period));
	}

	/** `obv()` — On-Balance Volume: cumulative signed-volume series. */
	public static function obv(harness:HarnessContext):Float {
		if (harness.currentBar == null) return Math.NaN;
		var v = harness.barIndicators.update("obv", harness.currentBar,
			() -> new Obv(),
			(ind, bar) -> (cast ind : Obv).update(bar));
		return v == null ? Math.NaN : (v : Float);
	}

	/** `williams_r(period)` — `-100 * (HH - close) / (HH - LL)` over the lookback window. */
	public static function williamsR(harness:HarnessContext, period:Int):Float {
		if (harness.currentBar == null) return Math.NaN;
		var v = harness.barIndicators.update("williams_r:" + period, harness.currentBar,
			() -> new WilliamsR(period),
			(ind, bar) -> (cast ind : WilliamsR).update(bar));
		return v == null ? Math.NaN : (v : Float);
	}

	/** `aroon(period)` — `{up, down}` strengths in [0, 100]. NaN-filled during warmup. */
	public static function aroon(harness:HarnessContext, period:Int):AroonOutput {
		if (harness.currentBar == null) return { up: Math.NaN, down: Math.NaN };
		var v:AroonOutput = harness.barIndicators.update("aroon:" + period, harness.currentBar,
			() -> new Aroon(period),
			(ind, bar) -> (cast ind : Aroon).update(bar));
		return v == null ? { up: Math.NaN, down: Math.NaN } : v;
	}

	/** `cci(period, ?factor)` — Commodity Channel Index; `factor` defaults to the canonical 0.015. */
	public static function cci(harness:HarnessContext, period:Int, ?factor:Float):Float {
		if (harness.currentBar == null) return Math.NaN;
		var key = "cci:" + period + ":" + (factor != null ? factor : 0.015);
		var v = harness.barIndicators.update(key, harness.currentBar,
			() -> new Cci(period, factor),
			(ind, bar) -> (cast ind : Cci).update(bar));
		return v == null ? Math.NaN : (v : Float);
	}

	/** `mfi(period)` — Money Flow Index: a volume-weighted RSI. */
	public static function mfi(harness:HarnessContext, period:Int):Float {
		if (harness.currentBar == null) return Math.NaN;
		var v = harness.barIndicators.update("mfi:" + period, harness.currentBar,
			() -> new Mfi(period),
			(ind, bar) -> (cast ind : Mfi).update(bar));
		return v == null ? Math.NaN : (v : Float);
	}
}
