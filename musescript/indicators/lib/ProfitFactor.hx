package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rolling Profit Factor — ported from wickra-core's `ProfitFactor`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/profit_factor.rs).
 *
 * Input is treated as a per-period return (or a per-trade P&L). Over the
 * trailing window: PF = Σ max(0, r) / Σ max(0, −r).
 * PF > 1 means the strategy made more than it lost in the window.
 */
class ProfitFactor implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "ProfitFactor: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return null;
		}
		window.push(input);
		if (window.length < period) {
			return null;
		}
		var gains:Float = 0.0;
		var losses:Float = 0.0;
		for (i in 0...window.length) {
			var r = window.oldest(i);
			if (r > 0.0) {
				gains += r;
			} else if (r < 0.0) {
				losses += -r;
			}
		}
		if (losses == 0.0) {
			return if (gains == 0.0) 0.0 else Math.POSITIVE_INFINITY;
		}
		return gains / losses;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "ProfitFactor";

	public static function spec():IndicatorSpec {
		return {
			name: "profit_factor", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalSeries(h, "profit_factor:" + p, "close", Math.NaN,
					() -> new ProfitFactor(p), (i, v) -> (cast i : ProfitFactor).update(v));
			}
		};
	}
}
