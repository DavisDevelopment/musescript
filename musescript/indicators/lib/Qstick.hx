package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Qstick — ported from wickra-core's `Qstick`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/qstick.rs).
 *
 *   Qstick = SMA(close - open, period)
 *
 * Tushar Chande's measure of buying vs. selling pressure: positive values
 * mean a run of bars closing above their open, negative values net selling
 * pressure. Reference: *The New Technical Trader*, 1994.
 */
class Qstick implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var sma:Sma;

	public function new(period:Int) {
		if (period <= 0) throw "Qstick: period must be > 0";
		this.period = period;
		sma = new Sma(period);
	}

	public function update(bar:Bar):Null<Float> {
		return sma.update(bar.close - bar.open);
	}

	public function reset():Void {
		sma.reset();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return sma.isReady();
	public function name():String return "Qstick";

	public static function spec():IndicatorSpec {
		return {
			name: "qstick", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 8);
				return IndicatorCache.evalBar(h, "qstick:" + p, Math.NaN,
					() -> new Qstick(p), (i, b) -> (cast i : Qstick).update(b));
			}
		};
	}
}
