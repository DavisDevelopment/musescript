package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Regime Label — ported from wickra-core's `RegimeLabel`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/regime_label.rs).
 *
 * Discrete {-1, 0, +1} classification of current volatility regime by quartile.
 * -1 = calm (vol < q1), +1 = stressed (vol > q3), 0 = normal.
 *
 * The lookback vol envelope is maintained via `SortedWindow` (order stats for
 * Q1/Q3 without a per-bar re-sort). The return window for the inner sample
 * vol still uses a plain Array — that path has no order-statistic sort.
 */
class RegimeLabel implements MuseIndicator<Float, Float> {
	var volPeriod:Int;
	var lookback:Int;
	var prevPrice:Null<Float>;
	var retWindow:RingBuffer<Float>;
	var retSum:Float;
	var retSumSq:Float;
	var volWindow:SortedWindow;
	var last:Null<Float>;

	public function new(volPeriod:Int, lookback:Int) {
		if (volPeriod < 2) throw "RegimeLabel: volPeriod must be >= 2";
		if (lookback < 2) throw "RegimeLabel: lookback must be >= 2";

		this.volPeriod = volPeriod;
		this.lookback = lookback;
		prevPrice = null;
		retWindow = new RingBuffer(volPeriod);
		retSum = 0.0;
		retSumSq = 0.0;
		volWindow = new SortedWindow(lookback);
		last = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input) || input <= 0.0) {
			return last;
		}

		if (prevPrice == null) {
			prevPrice = input;
			return null;
		}

		var prev = prevPrice;
		prevPrice = input;

		// Compute log return
		var r = Math.log(input / prev);

		// Roll the return window and its running moments
		var wasFull = retWindow.isFull();
		var old = retWindow.push(r);
		if (wasFull) {
			retSum -= old;
			retSumSq -= old * old;
		}
		retSum += r;
		retSumSq += r * r;

		if (retWindow.length < volPeriod) {
			return null;
		}

		// Compute volatility (sample standard deviation)
		var n = volPeriod;
		var nf = n;
		var mean = retSum / nf;
		var variance = Math.max(0.0, (retSumSq - nf * mean * mean) / (nf - 1.0));
		var vol = Math.sqrt(variance);

		volWindow.push(vol);
		if (volWindow.length < lookback) {
			return null;
		}

		var q1 = volWindow.quantile(0.25);
		var q3 = volWindow.quantile(0.75);

		// Classify
		var label = if (vol < q1) {
			-1.0;
		} else if (vol > q3) {
			1.0;
		} else {
			0.0;
		};

		last = label;
		return label;
	}

	public function reset():Void {
		prevPrice = null;
		retWindow = new RingBuffer(volPeriod);
		retSum = 0.0;
		retSumSq = 0.0;
		volWindow = new SortedWindow(lookback);
		last = null;
	}

	public function warmupPeriod():Int return volPeriod + lookback;
	public function isReady():Bool return last != null;
	public function name():String return "RegimeLabel";

	public static function spec():IndicatorSpec {
		return {
			name: "regime_label", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var vp = IndicatorCache.intArg(args, 1, 5);
				var lb = IndicatorCache.intArg(args, 2, 20);
				return IndicatorCache.evalSeries(h, "regime_label:" + series + ":" + vp + ":" + lb, series, Math.NaN,
					() -> new RegimeLabel(vp, lb), (i, v) -> (cast i : RegimeLabel).update(v));
			}
		};
	}
}
