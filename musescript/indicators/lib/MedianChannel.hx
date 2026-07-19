package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Median Channel output: window extremes plus the smoothed median center. */
typedef MedianChannelOutput = {
	var upper:Float;
	var median:Float;
	var lower:Float;
}

/**
 * Median Channel: a Donchian-style envelope (highest/lowest of the trailing
 * window) with the *median* of the window as the center line, rather than
 * the mean of the two extremes — more robust to a single outlier bar than
 * `Donchian`'s midline.
 */
class MedianChannel implements MuseIndicator<Float, MedianChannelOutput> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "MedianChannel: period must be >= 2";
		this.period = period;
		window = [];
	}

	public function update(price:Float):Null<MedianChannelOutput> {
		if (!Math.isFinite(price)) return null;
		if (window.length == period) window.shift();
		window.push(price);
		if (window.length < period) return null;

		var sorted = window.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var n = sorted.length;
		var med = n % 2 == 1 ? sorted[Std.int(n / 2)] : (sorted[Std.int(n / 2) - 1] + sorted[Std.int(n / 2)]) / 2.0;

		return { upper: sorted[n - 1], median: med, lower: sorted[0] };
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "MedianChannel";

	public static function spec():IndicatorSpec {
		return {
			name: "median_channel", args: [TSeries, TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "median", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var key = "median_channel:" + series + ":" + p;
				return IndicatorCache.evalSeries(h, key, series, { upper: Math.NaN, median: Math.NaN, lower: Math.NaN },
					() -> new MedianChannel(p), (i, v) -> (cast i : MedianChannel).update(v));
			}
		};
	}
}
