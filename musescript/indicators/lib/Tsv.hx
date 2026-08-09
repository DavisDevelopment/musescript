package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Time Segmented Volume (Don Worden) — ported from wickra-core's `Tsv`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/tsv.rs).
 *
 *   flow_t = (close_t - close_{t-1}) * volume_t     (signed money flow)
 *   TSV_t  = rolling window sum of the last `period` flows
 *
 * The first candle only seeds the previous close; the first TSV emission
 * lands at bar `period + 1`.
 */
class Tsv implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var prevClose:Null<Float>;
	var window:RingBuffer<Float>;
	var sum:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Tsv: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = bar.close;
			return null;
		}
		var flow = (bar.close - prevClose) * bar.volume;
		prevClose = bar.close;

		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(flow);
		if (wasFull) sum -= old;
		sum += flow;
		if (window.length < period) return null;
		return sum;
	}

	public function reset():Void {
		prevClose = null;
		window = new RingBuffer(period);
		sum = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "TSV";

	public static function spec():IndicatorSpec {
		return {
			name: "tsv", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 18);
				return IndicatorCache.evalBar(h, "tsv:" + p, Math.NaN,
					() -> new Tsv(p), (i, b) -> (cast i : Tsv).update(b));
			}
		};
	}
}
