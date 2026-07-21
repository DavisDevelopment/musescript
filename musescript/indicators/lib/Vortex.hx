package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Vortex Indicator output: the two directional movement lines. */
typedef VortexOutput = {
	var vi_plus:Float;
	var vi_minus:Float;
}

/**
 * Vortex Indicator — ported from wickra-core's `Vortex`
 * (vendor/wickra/crates/wickra-core/src/indicators/vortex.rs).
 *
 * Botes & Siepman's pair of oscillators (VI+, VI−):
 *
 *   VM+_t = |high_t − low_{t−1}|
 *   VM−_t = |low_t  − high_{t−1}|
 *   VI+   = Σ VM+ over n / Σ TR over n
 *   VI−   = Σ VM− over n / Σ TR over n
 *
 * VI+ crossing above VI− is bullish, the reverse bearish. A fully flat
 * window (zero true range) reports (0, 0). First value after `period + 1`
 * candles.
 */
class Vortex implements MuseIndicator<Bar, VortexOutput> {
	var period:Int;
	var prev:Null<Bar>;
	/** Rolling window of (VM+, VM−, TR) triples. */
	var window:Array<{p:Float, m:Float, tr:Float}>;
	var sumVmPlus:Float;
	var sumVmMinus:Float;
	var sumTr:Float;
	var last:Null<VortexOutput>;

	public function new(period:Int) {
		if (period <= 0) throw "Vortex: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(candle:Bar):Null<VortexOutput> {
		if (prev == null) {
			// The first bar has no predecessor to measure against.
			prev = candle;
			return null;
		}
		var vmPlus = Math.abs(candle.high - prev.low);
		var vmMinus = Math.abs(candle.low - prev.high);
		var hl = candle.high - candle.low;
		var hc = Math.abs(candle.high - prev.close);
		var lc = Math.abs(candle.low - prev.close);
		var tr = Math.max(hl, Math.max(hc, lc));
		prev = candle;

		if (window.length == period) {
			var old = window.shift();
			sumVmPlus -= old.p;
			sumVmMinus -= old.m;
			sumTr -= old.tr;
		}
		window.push({p: vmPlus, m: vmMinus, tr: tr});
		sumVmPlus += vmPlus;
		sumVmMinus += vmMinus;
		sumTr += tr;

		if (window.length < period) return null;
		var out:VortexOutput = if (sumTr == 0.0) {
			// A perfectly flat window has no range to normalise against.
			{ vi_plus: 0.0, vi_minus: 0.0 };
		} else {
			{ vi_plus: sumVmPlus / sumTr, vi_minus: sumVmMinus / sumTr };
		}
		last = out;
		return out;
	}

	public function reset():Void {
		prev = null;
		window = [];
		sumVmPlus = 0.0;
		sumVmMinus = 0.0;
		sumTr = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "Vortex";

	public static function spec():IndicatorSpec {
		return {
			name: "vortex", args: [TWindow], ret: TObject([
				{name: "vi_plus", ty: TScalar}, {name: "vi_minus", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var nanFill = { vi_plus: Math.NaN, vi_minus: Math.NaN };
				return IndicatorCache.evalBar(h, "vortex:" + p, nanFill,
					() -> new Vortex(p), (i, b) -> (cast i : Vortex).update(b));
			}
		};
	}
}
