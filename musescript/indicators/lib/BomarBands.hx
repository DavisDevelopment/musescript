package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Bomar Bands output: upper/middle/lower bands. */
typedef BomarBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Bomar Bands — ported from wickra-core's `BomarBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/bomar_bands.rs).
 *
 * Adaptive percentage bands whose width adjusts so that a fixed `coverage`
 * fraction of recent closes falls inside them. Unlike Bollinger Bands, the
 * width is an order statistic of the actual deviations rather than a multiple
 * of the standard deviation.
 *
 * middle = SMA(close, period)
 * dev_i  = |close_i / middle - 1|      // relative distance from midline
 * p      = coverage-quantile of {dev_i}  // type-7 interpolation
 * upper  = middle + |middle| * p
 * lower  = middle - |middle| * p
 */
class BomarBands implements MuseIndicator<Float, BomarBandsOutput> {
	var period:Int;
	var coverage:Float;
	var window:Array<Float>;
	var scratch:Array<Float>;

	public function new(period:Int, coverage:Float) {
		if (period <= 0) throw "BomarBands: period must be > 0";
		if (!Math.isFinite(coverage) || coverage <= 0.0 || coverage > 1.0) {
			throw "BomarBands: coverage must be a finite value in (0.0, 1.0]";
		}
		this.period = period;
		this.coverage = coverage;
		window = [];
		scratch = [];
	}

	/**
	 * Type-7 interpolation quantile (linear interpolation) of a sorted, non-empty array.
	 */
	function quantileSorted(sorted:Array<Float>, q:Float):Float {
		var lastIndex = sorted.length - 1;
		var rank = (q / 100.0) * lastIndex;
		var floor = Math.floor(rank);
		var lower = Std.int(floor);
		if (lower >= lastIndex) {
			return sorted[lastIndex];
		}
		var frac = rank - floor;
		return sorted[lower] + frac * (sorted[lower + 1] - sorted[lower]);
	}

	public function update(value:Float):Null<BomarBandsOutput> {
		if (!Math.isFinite(value)) return null;
		if (window.length == period) {
			window.shift();
		}
		window.push(value);
		if (window.length < period) return null;

		var sum = 0.0;
		for (v in window) sum += v;
		var middle = sum / period;
		var denom = Math.abs(middle);

		scratch = [];
		for (v in window) {
			var dev = if (denom == 0.0) {
				0.0;
			} else {
				Math.abs((v - middle) / denom);
			};
			scratch.push(dev);
		}
		scratch.sort(function(a, b) {
			if (a < b) return -1;
			if (a > b) return 1;
			return 0;
		});

		var p = quantileSorted(scratch, coverage * 100.0);
		var offset = denom * p;

		return {
			upper: middle + offset,
			middle: middle,
			lower: middle - offset
		};
	}

	public function reset():Void {
		window = [];
		scratch = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "BomarBands";

	public static function spec():IndicatorSpec {
		return {
			name: "bomar_bands", args: [TSeries, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var period = IndicatorCache.intArg(args, 1, 20);
				var coverage = IndicatorCache.floatArg(args, 2, 0.85);
				var key = "bomar_bands:" + series + ":" + period + ":" + coverage;
				return IndicatorCache.evalSeries(h, key, series, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new BomarBands(period, coverage), (i, v) -> (cast i : BomarBands).update(v));
			}
		};
	}
}
