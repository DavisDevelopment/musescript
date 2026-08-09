package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/** Quartile Bands output: upper (Q3), middle (median), lower (Q1) */
typedef QuartileBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Quartile Bands — ported from wickra-core's `QuartileBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/quartile_bands.rs).
 *
 * A distribution-based envelope drawn at the rolling quartiles (25th, 50th, 75th percentiles).
 * Non-parametric, robust to outliers.
 */
class QuartileBands implements MuseIndicator<Float, QuartileBandsOutput> {
	var period:Int;
	var window:SortedWindow;

	public function new(period:Int) {
		if (period <= 0) throw "QuartileBands: period must be > 0";
		this.period = period;
		window = new SortedWindow(period);
	}

	public function update(value:Float):Null<QuartileBandsOutput> {
		if (!Math.isFinite(value)) {
			return null;
		}
		window.push(value);
		if (window.length < period) {
			return null;
		}
		return {
			upper: window.quantile(0.75),
			middle: window.quantile(0.5),
			lower: window.quantile(0.25)
		};
	}

	public function reset():Void {
		window = new SortedWindow(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "QuartileBands";

	public static function spec():IndicatorSpec {
		return {
			name: "quartile_bands", args: [TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill:QuartileBandsOutput = {upper: Math.NaN, middle: Math.NaN, lower: Math.NaN};
				return IndicatorCache.evalSeries(h, "quartile_bands:" + p, "close", nanFill,
					() -> new QuartileBands(p), (i, v) -> (cast i : QuartileBands).update(v));
			}
		};
	}
}
