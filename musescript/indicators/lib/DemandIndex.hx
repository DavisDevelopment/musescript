package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Demand Index (James Sibbet) — ported from wickra-core's `DemandIndex`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/demand_index.rs).
 *
 * A smoothed ratio of buying to selling pressure, classifying each bar's volume
 * by whether the close rose or fell relative to the previous close.
 *
 * ```
 * pressure_t = volume_t · ((close_t − close_{t−1}) / max(close_{t−1}, ε))
 *              · (1 + (high_t − low_t) / max(close_{t−1}, ε))
 * DI_t       = EMA(pressure, period)_t
 * ```
 *
 * Positive readings mean the smoothed money flow is leaning to the buy side,
 * negative to the sell side. The first bar establishes the previous close only,
 * so the first non-null value lands once the EMA has accumulated `period`
 * pressure samples.
 */
class DemandIndex implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var ema:Ema;
	var prevClose:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "DemandIndex: period must be > 0";
		this.period = period;
		this.ema = new Ema(period);
		this.prevClose = null;
	}

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = bar.close;
			return null;
		}
		var prev = prevClose;
		var pressure = if (prev == 0.0) {
			// No prior baseline -> can't normalise; treat as no flow.
			0.0;
		} else {
			var ret = (bar.close - prev) / prev;
			var rangeNorm = (bar.high - bar.low) / prev;
			bar.volume * ret * (1.0 + rangeNorm);
		}
		prevClose = bar.close;
		return ema.update(pressure);
	}

	public function reset():Void {
		ema.reset();
		prevClose = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return ema.isReady();
	public function name():String return "DI";

	public static function spec():IndicatorSpec {
		return {
			name: "demand_index", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				return IndicatorCache.evalBar(h, "demand_index:" + p, Math.NaN,
					() -> new DemandIndex(p), (i, b) -> (cast i : DemandIndex).update(b));
			}
		};
	}
}
