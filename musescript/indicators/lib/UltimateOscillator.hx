package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ultimate Oscillator — ported from wickra-core's `UltimateOscillator`
 * (vendor/wickra/crates/wickra-core/src/indicators/ultimate_oscillator.rs).
 *
 * Larry Williams' three-timeframe momentum oscillator:
 *
 *   true_low_t = min(low_t, close_{t−1})
 *   BP_t       = close_t − true_low_t                  (buying pressure)
 *   TR_t       = max(high_t, close_{t−1}) − true_low_t (true range)
 *   avg_n      = Σ BP over n / Σ TR over n
 *   UO         = 100 · (4·avg_short + 2·avg_mid + avg_long) / 7
 *
 * Conventional periods 7/14/28, bounded [0, 100]. A fully flat window (zero
 * true range) contributes the neutral ratio 0.5, so a flat market reads 50.
 * First value after `max(short, mid, long) + 1` bars.
 */
class UltimateOscillator implements MuseIndicator<Bar, Float> {
	var short:Int;
	var mid:Int;
	var long:Int;
	var longest:Int;
	var prevClose:Null<Float>;
	/** Rolling window of (buying_pressure, true_range) pairs. */
	var window:Array<{bp:Float, tr:Float}>;
	var sumBpShort:Float;
	var sumTrShort:Float;
	var sumBpMid:Float;
	var sumTrMid:Float;
	var sumBpLong:Float;
	var sumTrLong:Float;
	var pairs:Int;
	var last:Null<Float>;

	public function new(short:Int, mid:Int, long:Int) {
		if (short <= 0 || mid <= 0 || long <= 0) throw "UltimateOscillator: period must be > 0";
		this.short = short;
		this.mid = mid;
		this.long = long;
		longest = Std.int(Math.max(short, Math.max(mid, long)));
		reset();
	}

	/** Classic Ultimate Oscillator: periods 7, 14, 28. */
	public static function classic():UltimateOscillator {
		return new UltimateOscillator(7, 14, 28);
	}

	public function update(candle:Bar):Null<Float> {
		if (prevClose == null) {
			// The first bar has no previous close, so no BP/TR can be formed.
			prevClose = candle.close;
			return null;
		}
		var pc:Float = prevClose;
		prevClose = candle.close;

		var trueLow = Math.min(candle.low, pc);
		var bp = candle.close - trueLow;
		var tr = Math.max(candle.high, pc) - trueLow;

		window.push({bp: bp, tr: tr});
		var n = window.length;
		sumBpShort += bp;
		sumTrShort += tr;
		sumBpMid += bp;
		sumTrMid += tr;
		sumBpLong += bp;
		sumTrLong += tr;
		if (n > short) {
			var o = window[n - 1 - short];
			sumBpShort -= o.bp;
			sumTrShort -= o.tr;
		}
		if (n > mid) {
			var o = window[n - 1 - mid];
			sumBpMid -= o.bp;
			sumTrMid -= o.tr;
		}
		if (n > long) {
			var o = window[n - 1 - long];
			sumBpLong -= o.bp;
			sumTrLong -= o.tr;
		}
		if (window.length > longest) window.shift();

		pairs++;
		if (pairs < longest) return null;

		// A fully flat window has no range; contribute the midpoint 0.5.
		var avgShort = sumTrShort == 0.0 ? 0.5 : sumBpShort / sumTrShort;
		var avgMid = sumTrMid == 0.0 ? 0.5 : sumBpMid / sumTrMid;
		var avgLong = sumTrLong == 0.0 ? 0.5 : sumBpLong / sumTrLong;
		var uo = 100.0 * (4.0 * avgShort + 2.0 * avgMid + avgLong) / 7.0;
		last = uo;
		return uo;
	}

	public function reset():Void {
		prevClose = null;
		window = [];
		sumBpShort = 0.0;
		sumTrShort = 0.0;
		sumBpMid = 0.0;
		sumTrMid = 0.0;
		sumBpLong = 0.0;
		sumTrLong = 0.0;
		pairs = 0;
		last = null;
	}

	public function warmupPeriod():Int return longest + 1;
	public function isReady():Bool return last != null;
	public function name():String return "UltimateOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "ultimate_oscillator", args: [TWindow, TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var s = args.length > 0 ? IndicatorCache.intArg(args, 0, 7) : 7;
				var m = IndicatorCache.intArg(args, 1, 14);
				var l = IndicatorCache.intArg(args, 2, 28);
				return IndicatorCache.evalBar(h, "ultimate_oscillator:" + s + ":" + m + ":" + l, Math.NaN,
					() -> new UltimateOscillator(s, m, l), (i, b) -> (cast i : UltimateOscillator).update(b));
			}
		};
	}
}
