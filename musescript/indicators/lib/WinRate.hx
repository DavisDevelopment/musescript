package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Win Rate — ported from wickra-core's `WinRate`
 * (vendor/wickra/crates/wickra-core/src/indicators/win_rate.rs).
 *
 * The fraction of strictly-positive returns among the last `period` returns,
 * in `[0, 1]`: `WinRate = #(rᵢ > 0) / period`. A return of exactly 0 is a
 * non-win (flat / scratch). O(1) per update — the win count is maintained
 * incrementally.
 */
class WinRate implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var wins:Int;

	public function new(period:Int) {
		if (period == 0) throw "WinRate: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(ret:Float):Null<Float> {
		if (!Math.isFinite(ret)) return null;
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(ret);
		if (wasFull) {
			if (old > 0.0) wins--;
		}
		if (ret > 0.0) wins++;
		if (window.length < period) return null;
		return wins / period;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		wins = 0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "WinRate";

	public static function spec():IndicatorSpec {
		return {
			name: "win_rate", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "win_rate:" + series + ":" + p, series, Math.NaN,
					() -> new WinRate(p), (i, v) -> (cast i : WinRate).update(v));
			}
		};
	}
}
