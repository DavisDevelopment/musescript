package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Upside Potential Ratio (Sortino, van der Meer & Plantinga) — ported from
 * wickra-core's `UpsidePotentialRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/upside_potential_ratio.rs).
 *
 * Over a trailing window of `period` returns, relative to a minimal
 * acceptable return `mar`:
 *
 * upside   = mean( max(r − mar, 0) )
 * downside = sqrt( mean( min(r − mar, 0)² ) )
 * UPR      = upside / downside
 *
 * Rewards only average outperformance above the threshold while penalising
 * solely downside deviation below it. A window that never breaches the
 * threshold reports `0.0` rather than dividing by zero. O(1) per update via
 * running upside-total and downside sum-of-squares.
 */
class UpsidePotentialRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var mar:Float;
	var window:Array<Float>;
	var sumUpside:Float;
	var sumDownsideSq:Float;

	public function new(period:Int, mar:Float) {
		if (period < 2) throw "UpsidePotentialRatio: upside potential ratio needs period >= 2";
		if (!Math.isFinite(mar)) throw "UpsidePotentialRatio: mar must be finite";
		this.period = period;
		this.mar = mar;
		reset();
	}

	public function update(ret:Float):Null<Float> {
		if (!Math.isFinite(ret)) return null;
		if (window.length == period) {
			var old = window.shift();
			var oldExcess = old - mar;
			sumUpside -= oldExcess > 0.0 ? oldExcess : 0.0;
			var oldDown = oldExcess < 0.0 ? oldExcess : 0.0;
			sumDownsideSq -= oldDown * oldDown;
		}
		var excess = ret - mar;
		sumUpside += excess > 0.0 ? excess : 0.0;
		var down = excess < 0.0 ? excess : 0.0;
		sumDownsideSq += down * down;
		window.push(ret);
		if (window.length < period) return null;
		var n = period;
		var upsideMean = sumUpside / n;
		var downsideDev = Math.sqrt(sumDownsideSq / n);
		return downsideDev > 0.0 ? upsideMean / downsideDev : 0.0;
	}

	public function reset():Void {
		window = [];
		sumUpside = 0.0;
		sumDownsideSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "UpsidePotentialRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "upside_potential_ratio", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var mar = IndicatorCache.floatArg(args, 2, 0.0);
				var key = "upside_potential_ratio:" + series + ":" + p + ":" + mar;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new UpsidePotentialRatio(p, mar), (i, v) -> (cast i : UpsidePotentialRatio).update(v));
			}
		};
	}
}
