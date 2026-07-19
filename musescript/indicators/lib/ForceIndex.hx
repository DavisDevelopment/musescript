package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Force Index: combines a bar's price change and volume into a single
 * momentum/volume measure, smoothed with an EMA.
 *
 * raw_t = (close_t - close_{t-1}) * volume_t
 * ForceIndex = EMA(raw, period)
 */
class ForceIndex implements MuseIndicator<Bar, Float> {
	var ema:Ema;
	var hasPrevClose:Bool;
	var prevClose:Float;

	public function new(period:Int) {
		ema = new Ema(period);
		hasPrevClose = false;
		prevClose = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var raw = 0.0;
		if (hasPrevClose) raw = (bar.close - prevClose) * bar.volume;
		prevClose = bar.close;
		hasPrevClose = true;
		return ema.update(raw);
	}

	public function reset():Void {
		ema.reset();
		hasPrevClose = false;
		prevClose = 0.0;
	}

	public function warmupPeriod():Int return ema.period + 1;
	public function isReady():Bool return ema.isReady();
	public function name():String return "ForceIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "force_index", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 13);
				return IndicatorCache.evalBar(h, "force_index:" + p, Math.NaN,
					() -> new ForceIndex(p), (i, b) -> (cast i : ForceIndex).update(b));
			}
		};
	}
}
