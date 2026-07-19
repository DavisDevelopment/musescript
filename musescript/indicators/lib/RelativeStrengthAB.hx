package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.indicators.prim.Rsi;
import musescript.types.MuseType;

/**
 * Relative Strength A vs B — ported from wickra-core's `RelativeStrengthAB`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/relative_strength_ab.rs).
 *
 * Comparative relative strength of asset a against asset b. The indicator
 * forms the ratio line a/b, smooths it with a simple moving average, and runs
 * it through an RSI. The output includes the raw ratio, its MA, and its RSI.
 *
 * A rising ratio means a is outperforming b; ratio_ma shows the trend; ratio_rsi
 * flags exhaustion (e.g. > 70 after a strong run).
 */
typedef RelativeStrengthOutput = {
	ratio: Float,
	ratio_ma: Float,
	ratio_rsi: Float
};

class RelativeStrengthAB implements MuseIndicator<RSPair, RelativeStrengthOutput> {
	var maPeriod:Int;
	var rsiPeriod:Int;
	var ma:Sma;
	var rsi:Rsi;

	public function new(maPeriod:Int, rsiPeriod:Int) {
		if (maPeriod <= 0) throw "RelativeStrengthAB: ma_period must be > 0";
		if (rsiPeriod <= 0) throw "RelativeStrengthAB: rsi_period must be > 0";
		this.maPeriod = maPeriod;
		this.rsiPeriod = rsiPeriod;
		ma = new Sma(maPeriod);
		rsi = new Rsi(rsiPeriod);
	}

	public function update(input:RSPair):Null<RelativeStrengthOutput> {
		var a = input.a;
		var b = input.b;
		if (b == 0.0 || !Math.isFinite(a) || !Math.isFinite(b)) {
			// Undefined ratio: skip without disturbing the internal averages.
			return null;
		}
		var ratio = a / b;
		var maVal = ma.update(ratio);
		var rsiVal = rsi.update(ratio);
		if (maVal != null && rsiVal != null) {
			return {
				ratio: ratio,
				ratio_ma: maVal,
				ratio_rsi: rsiVal
			};
		}
		return null;
	}

	public function reset():Void {
		ma.reset();
		rsi.reset();
	}

	public function warmupPeriod():Int {
		var maWarmup = ma.warmupPeriod();
		var rsiWarmup = rsi.warmupPeriod();
		return maWarmup > rsiWarmup ? maWarmup : rsiWarmup;
	}

	public function isReady():Bool {
		return ma.isReady() && rsi.isReady();
	}

	public function name():String return "RelativeStrengthAB";

	public static function spec():IndicatorSpec {
		return {
			name: "relative_strength_ab",
			args: [TSeries, TSeries, TWindow, TWindow],
			ret: TObject([
				{name: "ratio", ty: TScalar},
				{name: "ratio_ma", ty: TScalar},
				{name: "ratio_rsi", ty: TScalar}
			]),
			minArgs: 4,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var mp = IndicatorCache.intArg(args, 2, 10);
				var rp = IndicatorCache.intArg(args, 3, 14);
				var key = "relative_strength_ab:" + seriesA + ":" + seriesB + ":" + mp + ":" + rp;
				var nanFill:RelativeStrengthOutput = {
					ratio: Math.NaN,
					ratio_ma: Math.NaN,
					ratio_rsi: Math.NaN
				};
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, nanFill,
					() -> new RelativeStrengthAB(mp, rp),
					(i, a, b) -> (cast i : RelativeStrengthAB).update({ a: a, b: b }));
			}
		};
	}
}

typedef RSPair = { a: Float, b: Float };
