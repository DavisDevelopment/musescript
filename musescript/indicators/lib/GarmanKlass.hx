package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Garman-Klass volatility estimator: a more efficient realized-volatility
 * estimate than close-to-close stddev, since it also uses each bar's own
 * high/low/open/close range and body.
 *
 * perBar = 0.5*ln(H/L)^2 - (2*ln(2) - 1)*ln(C/O)^2
 * GK = sqrt( mean(perBar, period) )
 *
 * Falls back to a 0 per-bar contribution on a non-positive OHLC value
 * (undefined log), so a corrupt bar dilutes rather than crashes the window.
 */
class GarmanKlass implements MuseIndicator<Bar, Float> {
	static var TWO_LN2_MINUS_1:Float = 2.0 * Math.log(2.0) - 1.0;

	var period:Int;
	var window:Array<Float>;
	var sum:Float;

	public function new(period:Int) {
		if (period <= 0) throw "GarmanKlass: period must be > 0";
		this.period = period;
		window = [];
		sum = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var perBar = 0.0;
		if (bar.high > 0.0 && bar.low > 0.0 && bar.close > 0.0 && bar.open > 0.0) {
			var hl = Math.log(bar.high / bar.low);
			var co = Math.log(bar.close / bar.open);
			perBar = 0.5 * hl * hl - TWO_LN2_MINUS_1 * co * co;
		}

		if (window.length == period) sum -= window.shift();
		window.push(perBar);
		sum += perBar;

		if (window.length < period) return null;
		var mean = sum / period;
		return Math.sqrt(Math.max(0.0, mean));
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "GarmanKlass";

	public static function spec():IndicatorSpec {
		return {
			name: "garman_klass", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "garman_klass:" + p, Math.NaN,
					() -> new GarmanKlass(p), (i, b) -> (cast i : GarmanKlass).update(b));
			}
		};
	}
}
