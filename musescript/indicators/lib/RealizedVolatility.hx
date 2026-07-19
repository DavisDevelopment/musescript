package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Realized Volatility — ported from wickra-core's `RealizedVolatility`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/realized_volatility.rs).
 *
 * Square root of the sum of squared log returns over the trailing `period` bars.
 * Raw, un-annualized quadratic variation. Non-finite and non-positive prices are ignored.
 */
class RealizedVolatility implements MuseIndicator<Float, Float> {
	var period:Int;
	var prevPrice:Null<Float>;
	var window:Array<Float>;
	var sumSq:Float;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "RealizedVolatility: period must be > 0";
		this.period = period;
		prevPrice = null;
		window = [];
		sumSq = 0.0;
		last = null;
	}

	public function update(input:Float):Null<Float> {
		// Non-finite or non-positive prices are skipped
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

		// Roll the window of squared returns
		if (window.length == period) {
			var old = window.shift();
			sumSq -= old * old;
		}

		window.push(r);
		sumSq += r * r;

		if (window.length < period) {
			return null;
		}

		// Clamp to avoid floating-point subtraction artifacts
		var rv = Math.sqrt(Math.max(0.0, sumSq));
		last = rv;
		return rv;
	}

	public function reset():Void {
		prevPrice = null;
		window = [];
		sumSq = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "RealizedVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "realized_volatility", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "realized_volatility:" + series + ":" + p, series, Math.NaN,
					() -> new RealizedVolatility(p), (i, v) -> (cast i : RealizedVolatility).update(v));
			}
		};
	}
}
