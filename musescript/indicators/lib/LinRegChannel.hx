package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.LinReg.LinRegMath;
import musescript.types.MuseType;

/** Linear Regression Channel output: the fitted midline and its stddev-scaled bands. */
typedef LinRegChannelOutput = {
	var upper:Float;
	var mid:Float;
	var lower:Float;
}

/**
 * Linear Regression Channel: `LinReg`'s fitted line as the midline, with
 * bands offset by `multiplier` residual standard deviations — the
 * regression-based analogue of Bollinger Bands.
 *
 * mid   = LinReg(period)  (fitted value at the most recent point)
 * upper = mid + multiplier * residualStdDev
 * lower = mid - multiplier * residualStdDev
 */
class LinRegChannel implements MuseIndicator<Float, LinRegChannelOutput> {
	var period:Int;
	var multiplier:Float;
	var window:Array<Float>;

	public function new(period:Int, multiplier:Float) {
		if (period < 2) throw "LinRegChannel: period must be >= 2";
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "LinRegChannel: multiplier must be positive and finite";
		this.period = period;
		this.multiplier = multiplier;
		window = [];
	}

	public function update(price:Float):Null<LinRegChannelOutput> {
		if (!Math.isFinite(price)) return null;
		if (window.length == period) window.shift();
		window.push(price);
		if (window.length < period) return null;

		var fit = LinRegMath.fitLast(window);
		return { upper: fit.value + multiplier * fit.residualStdDev, mid: fit.value, lower: fit.value - multiplier * fit.residualStdDev };
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "LinRegChannel";

	public static function spec():IndicatorSpec {
		return {
			name: "linreg_channel", args: [TSeries, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "mid", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var m = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "linreg_channel:" + series + ":" + p + ":" + m;
				return IndicatorCache.evalSeries(h, key, series, { upper: Math.NaN, mid: Math.NaN, lower: Math.NaN },
					() -> new LinRegChannel(p, m), (i, v) -> (cast i : LinRegChannel).update(v));
			}
		};
	}
}
