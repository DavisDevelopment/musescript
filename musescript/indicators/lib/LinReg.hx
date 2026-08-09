package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Linear Regression (a.k.a. "Time Series Forecast"): the least-squares
 * fitted value at the most recent point of a trailing window of `period`
 * prices — the same "TSF" construction `Cfo`/`Inertia` build on, exposed
 * directly as its own indicator.
 *
 * fit(x) = intercept + slope*x, fit via ordinary least squares over x=0..n-1
 * LinReg = fit(n-1)     (the fitted value AT today, not a future extrapolation)
 */
class LinReg implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "LinReg: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		window.push(price);
		if (window.length < period) return null;

		var fit = LinRegMath.fitLast(window);
		return fit.value;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "LinReg";

	public static function spec():IndicatorSpec {
		return {
			name: "linreg", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "linreg:" + series + ":" + p, series, Math.NaN,
					() -> new LinReg(p), (i, v) -> (cast i : LinReg).update(v));
			}
		};
	}
}

/** Shared OLS-over-a-window helper for LinReg / LinRegAngle / LinRegChannel. */
class LinRegMath {
	public static function fitLast(window:RingBuffer<Float>):{value:Float, slope:Float, intercept:Float, residualStdDev:Float} {
		var n = window.length;
		var meanX = (n - 1) / 2.0;
		var meanY = 0.0;
		for (i in 0...n) meanY += window.oldest(i);
		meanY /= n;

		var num = 0.0;
		var den = 0.0;
		for (i in 0...n) {
			var dx = i - meanX;
			num += dx * (window.oldest(i) - meanY);
			den += dx * dx;
		}
		var slope = den == 0.0 ? 0.0 : num / den;
		var intercept = meanY - slope * meanX;

		var sse = 0.0;
		for (i in 0...n) {
			var fitted = intercept + slope * i;
			var resid = window.oldest(i) - fitted;
			sse += resid * resid;
		}
		var residualStdDev = Math.sqrt(sse / n);

		return { value: intercept + slope * (n - 1), slope: slope, intercept: intercept, residualStdDev: residualStdDev };
	}
}
