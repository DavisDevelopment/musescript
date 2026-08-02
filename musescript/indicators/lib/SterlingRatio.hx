package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Sterling Ratio — ported from wickra-core's `SterlingRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/sterling_ratio.rs).
 *
 * Over a trailing window of `period` returns:
 *
 * equity_t  = Π_{i<=t} (1 + return_i)          (compounded curve)
 * peak_t    = max_{s<=t} equity_s
 * dd_t      = (peak_t − equity_t) / peak_t
 * Sterling  = mean(returns) / mean(dd_t)
 *
 * Rewards return per unit of *typical* pain — the gentlest on outliers of
 * Wickra's drawdown-based ratios (Burke sums squared drawdowns, Martin uses
 * the RMS percentage drawdown). A window that never draws down reports `0.0`.
 */
class SterlingRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "SterlingRatio: sterling ratio needs period >= 2";
		this.period = period;
		reset();
	}

	function compute():Float {
		var length = window.length;
		var sumReturn = 0.0;
		var sumDrawdown = 0.0;
		var equity = 1.0;
		var peak = 1.0;
		for (ret in window) {
			sumReturn += ret;
			equity *= 1.0 + ret;
			if (equity > peak) peak = equity;
			sumDrawdown += (peak - equity) / peak;
		}
		var avgDrawdown = sumDrawdown / length;
		return avgDrawdown > 0.0 ? (sumReturn / length) / avgDrawdown : 0.0;
	}

	public function update(ret:Float):Null<Float> {
		if (!Math.isFinite(ret)) return null;
		window.push(ret);
		if (window.length < period) return null;
		return compute();
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SterlingRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "sterling_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 12);
				return IndicatorCache.evalSeries(h, "sterling_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new SterlingRatio(p), (i, v) -> (cast i : SterlingRatio).update(v));
			}
		};
	}
}
