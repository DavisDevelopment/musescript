package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Better Volume: the current bar's volume relative to its own trailing
 * simple-moving-average volume.
 *
 * BetterVolume = volume / SMA(volume, period)
 *
 * 1.0 means today's volume matches the recent average; > 1.0 flags
 * above-average participation (climax/breakout-confirmation bars), < 1.0
 * flags a quiet, low-conviction bar. Falls back to 1.0 when the average
 * volume is zero (an all-zero-volume window carries no relative signal).
 */
class BetterVolume implements MuseIndicator<Bar, Float> {
	var avgVolume:Sma;

	public function new(period:Int) {
		avgVolume = new Sma(period);
	}

	public function update(bar:Bar):Null<Float> {
		var avg = avgVolume.update(bar.volume);
		if (avg == null) return null;
		if (avg <= 0.0) return 1.0;
		return bar.volume / avg;
	}

	public function reset():Void {
		avgVolume.reset();
	}

	public function warmupPeriod():Int return avgVolume.period;
	public function isReady():Bool return avgVolume.isReady();
	public function name():String return "BetterVolume";

	public static function spec():IndicatorSpec {
		return {
			name: "better_volume", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "better_volume:" + p, Math.NaN,
					() -> new BetterVolume(p), (i, b) -> (cast i : BetterVolume).update(b));
			}
		};
	}
}
