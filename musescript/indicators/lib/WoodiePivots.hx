package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Woodie Pivot Points output: two resistances, pivot, two supports.
 *
 * NOTE: Rust's field is `pp`, renamed to `pivot` here — deliberately, twice
 * over: (1) it matches the ClassicPivots/DemarkPivots output convention, and
 * (2) `"pp"` and `"r2"` share the same Java String hashCode (3584), which
 * trips a Haxe JVM-backend codegen bug (duplicate lookupswitch keys in the
 * generated `_hx_setField` → `VerifyError: Bad lookupswitch instruction`),
 * found by the GraalVM indicator benchmark. Keep the names collision-free.
 */
typedef WoodiePivotsOutput = {
	var pivot:Float;
	var r1:Float;
	var r2:Float;
	var s1:Float;
	var s2:Float;
}

/**
 * Woodie Pivot Points — ported from wickra-core's `WoodiePivots`
 * (vendor/wickra/crates/wickra-core/src/indicators/woodie_pivots.rs).
 *
 * Tom Williams' close-weighted pivot variant:
 *
 *   PP = (H + L + 2·C) / 4
 *   R1 = 2·PP − L        S1 = 2·PP − H
 *   R2 = PP + (H − L)    S2 = PP − (H − L)
 *
 * The double-weighted close shifts the pivot toward where most of the
 * session's activity actually settled. Emits on every bar (warmup 1).
 */
class WoodiePivots implements MuseIndicator<Bar, WoodiePivotsOutput> {
	var ready:Bool;

	public function new() {
		ready = false;
	}

	public function update(candle:Bar):Null<WoodiePivotsOutput> {
		var h = candle.high;
		var l = candle.low;
		var c = candle.close;
		var pp = (h + l + 2.0 * c) / 4.0;
		var range = h - l;
		var out:WoodiePivotsOutput = {
			pivot: pp,
			r1: 2.0 * pp - l,
			r2: pp + range,
			s1: 2.0 * pp - h,
			s2: pp - range
		};
		ready = true;
		return out;
	}

	public function reset():Void {
		ready = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return ready;
	public function name():String return "WoodiePivots";

	public static function spec():IndicatorSpec {
		return {
			name: "woodie_pivots", args: [], ret: TObject([
				{name: "pivot", ty: TScalar}, {name: "r1", ty: TScalar}, {name: "r2", ty: TScalar},
				{name: "s1", ty: TScalar}, {name: "s2", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { pivot: Math.NaN, r1: Math.NaN, r2: Math.NaN, s1: Math.NaN, s2: Math.NaN };
				return IndicatorCache.evalBar(h, "woodie_pivots", nanFill,
					() -> new WoodiePivots(), (i, b) -> (cast i : WoodiePivots).update(b));
			}
		};
	}
}
