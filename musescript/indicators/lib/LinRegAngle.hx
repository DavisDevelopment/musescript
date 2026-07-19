package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.LinReg.LinRegMath;
import musescript.types.MuseType;

/**
 * Linear Regression Angle: the slope of `LinReg`'s fitted line expressed as
 * an angle in degrees, over the same trailing window of `period` prices.
 *
 * angle = atan(slope) * 180 / pi
 *
 * Positive means the fitted line points up, negative down; magnitude tracks
 * how steep the recent trend has been (independent of price's own scale is
 * NOT true here — like the raw slope, this is scale-sensitive; compare
 * across the same instrument, not across instruments of different price).
 */
class LinRegAngle implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "LinRegAngle: period must be >= 2";
		this.period = period;
		window = [];
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (window.length == period) window.shift();
		window.push(price);
		if (window.length < period) return null;

		var fit = LinRegMath.fitLast(window);
		return Math.atan(fit.slope) * 180.0 / Math.PI;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "LinRegAngle";

	public static function spec():IndicatorSpec {
		return {
			name: "linreg_angle", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "linreg_angle:" + series + ":" + p, series, Math.NaN,
					() -> new LinRegAngle(p), (i, v) -> (cast i : LinRegAngle).update(v));
			}
		};
	}
}
