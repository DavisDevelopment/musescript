package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.lib.LinReg.LinRegMath;
import musescript.types.MuseType;

/**
 * Linear Regression Intercept: the y-intercept (fitted value at x=0, i.e.
 * the OLDEST bar in the window) of `LinReg`'s fitted line over a trailing
 * window of `period` prices.
 */
class LinRegIntercept implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "LinRegIntercept: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		window.push(price);
		if (window.length < period) return null;
		return LinRegMath.fitLast(window).intercept;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "LinRegIntercept";

	public static function spec():IndicatorSpec {
		return {
			name: "linreg_intercept", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "linreg_intercept:" + series + ":" + p, series, Math.NaN,
					() -> new LinRegIntercept(p), (i, v) -> (cast i : LinRegIntercept).update(v));
			}
		};
	}
}
