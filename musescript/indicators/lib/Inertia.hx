package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Inertia (Donald Dorsey): a linear-regression-smoothed Relative Vigor
 * Index — RVI measures whether closes are settling higher within their
 * bars than they opened (vigor), and Inertia fits a trend line through
 * RVI's recent values to reduce its noise into a smoother directional read.
 *
 * RVI_t    = SMA(close - open, rviPeriod) / SMA(high - low, rviPeriod)
 * Inertia  = linreg-endpoint-fit(RVI, inertiaPeriod)
 *            (the least-squares fitted value at the most recent point in
 *            the RVI window — same "TSF" construction as `Cfo`)
 */
class Inertia implements MuseIndicator<Bar, Float> {
	var rviPeriod:Int;
	var bodyWindow:Array<Float>;
	var rangeWindow:Array<Float>;
	var sumBody:Float;
	var sumRange:Float;
	var rviWindow:Array<Float>;
	var inertiaPeriod:Int;

	public function new(rviPeriod:Int, inertiaPeriod:Int) {
		if (rviPeriod <= 0) throw "Inertia: rviPeriod must be > 0";
		if (inertiaPeriod < 2) throw "Inertia: inertiaPeriod must be >= 2";
		this.rviPeriod = rviPeriod;
		this.inertiaPeriod = inertiaPeriod;
		bodyWindow = [];
		rangeWindow = [];
		sumBody = 0.0;
		sumRange = 0.0;
		rviWindow = [];
	}

	public function update(bar:Bar):Null<Float> {
		var body = bar.close - bar.open;
		var range = bar.high - bar.low;

		if (bodyWindow.length == rviPeriod) sumBody -= bodyWindow.shift();
		bodyWindow.push(body);
		sumBody += body;
		if (rangeWindow.length == rviPeriod) sumRange -= rangeWindow.shift();
		rangeWindow.push(range);
		sumRange += range;

		if (bodyWindow.length < rviPeriod) return null;
		if (sumRange == 0.0) return null;
		var rvi = sumBody / sumRange;

		if (rviWindow.length == inertiaPeriod) rviWindow.shift();
		rviWindow.push(rvi);
		if (rviWindow.length < inertiaPeriod) return null;

		var n = rviWindow.length;
		var meanX = (n - 1) / 2.0;
		var meanY = 0.0;
		for (v in rviWindow) meanY += v;
		meanY /= n;

		var num = 0.0;
		var den = 0.0;
		for (i in 0...n) {
			var dx = i - meanX;
			num += dx * (rviWindow[i] - meanY);
			den += dx * dx;
		}
		if (den == 0.0) return rvi;
		var slope = num / den;
		var intercept = meanY - slope * meanX;
		return intercept + slope * (n - 1);
	}

	public function reset():Void {
		bodyWindow = [];
		rangeWindow = [];
		sumBody = 0.0;
		sumRange = 0.0;
		rviWindow = [];
	}

	public function warmupPeriod():Int return rviPeriod + inertiaPeriod;
	public function isReady():Bool return rviWindow.length == inertiaPeriod;
	public function name():String return "Inertia";

	public static function spec():IndicatorSpec {
		return {
			name: "inertia", args: [TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var rviPeriod = IndicatorCache.intArg(args, 0, 10);
				var inertiaPeriod = IndicatorCache.intArg(args, 1, 14);
				var key = "inertia:" + rviPeriod + ":" + inertiaPeriod;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new Inertia(rviPeriod, inertiaPeriod), (i, b) -> (cast i : Inertia).update(b));
			}
		};
	}
}
