package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Volume RSI — ported from wickra-core's `VolumeRsi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/volume_rsi.rs).
 *
 * Wilder's RSI accumulator applied to bar-over-bar volume changes instead of
 * price changes:
 *
 *   change_t = volume_t - volume_{t-1}
 *   gain = max(change, 0),  loss = max(-change, 0)
 *   VolumeRSI = 100 * avg_gain / (avg_gain + avg_loss)     (50 when both are 0)
 *
 * The first bar sets the previous volume, then `period` changes seed Wilder's
 * averages, so the first value lands after `period + 1` inputs.
 */
class VolumeRsi implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var prevVolume:Null<Float>;
	var seedGains:Float;
	var seedLosses:Float;
	var seedCount:Int;
	var avgGain:Null<Float>;
	var avgLoss:Null<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "VolumeRsi: period must be > 0";
		this.period = period;
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return last;

	static function rsiFromAvgs(avgGain:Float, avgLoss:Float):Float {
		var denom = avgGain + avgLoss;
		return denom == 0.0 ? 50.0 : 100.0 * (avgGain / denom);
	}

	public function update(bar:Bar):Null<Float> {
		var volume = bar.volume;
		if (prevVolume == null) {
			prevVolume = volume;
			return null;
		}
		var change = volume - prevVolume;
		prevVolume = volume;
		var gain = change > 0.0 ? change : 0.0;
		var loss = change < 0.0 ? -change : 0.0;

		if (avgGain != null && avgLoss != null) {
			var n:Float = period;
			var newAg = (avgGain * (n - 1.0) + gain) / n;
			var newAl = (avgLoss * (n - 1.0) + loss) / n;
			avgGain = newAg;
			avgLoss = newAl;
			var v = rsiFromAvgs(newAg, newAl);
			last = v;
			return v;
		}

		seedGains += gain;
		seedLosses += loss;
		seedCount += 1;
		if (seedCount == period) {
			var n:Float = period;
			var ag = seedGains / n;
			var al = seedLosses / n;
			avgGain = ag;
			avgLoss = al;
			var v = rsiFromAvgs(ag, al);
			last = v;
			return v;
		}
		return null;
	}

	public function reset():Void {
		prevVolume = null;
		seedGains = 0.0;
		seedLosses = 0.0;
		seedCount = 0;
		avgGain = null;
		avgLoss = null;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "VolumeRsi";

	public static function spec():IndicatorSpec {
		return {
			name: "volume_rsi", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "volume_rsi:" + p, Math.NaN,
					() -> new VolumeRsi(p), (i, b) -> (cast i : VolumeRsi).update(b));
			}
		};
	}
}
