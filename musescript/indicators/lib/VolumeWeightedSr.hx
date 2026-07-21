package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Volume-Weighted S/R output: the support and resistance levels. */
typedef VolumeWeightedSrOutput = {
	var support:Float;
	var resistance:Float;
}

/**
 * Volume-Weighted Support/Resistance — ported from wickra-core's `VolumeWeightedSr`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/volume_weighted_sr.rs).
 *
 *   support    = sum(low_i  * volume_i) / sum(volume_i)   over the window
 *   resistance = sum(high_i * volume_i) / sum(volume_i)   over the window
 *
 * If the window's volume is all zero the band falls back to the
 * equal-weighted average high and low. First value after `period` inputs.
 */
class VolumeWeightedSr implements MuseIndicator<Bar, VolumeWeightedSrOutput> {
	public var period(default, null):Int;
	var highs:Array<Float>;
	var lows:Array<Float>;
	var volumes:Array<Float>;
	var sumHv:Float;
	var sumLv:Float;
	var sumV:Float;
	var sumH:Float;
	var sumL:Float;
	var last:Null<VolumeWeightedSrOutput>;

	public function new(period:Int) {
		if (period <= 0) throw "VolumeWeightedSr: period must be > 0";
		this.period = period;
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<VolumeWeightedSrOutput> return last;

	public function update(bar:Bar):Null<VolumeWeightedSrOutput> {
		if (highs.length == period) {
			var h = highs.shift();
			var l = lows.shift();
			var v = volumes.shift();
			sumHv -= h * v;
			sumLv -= l * v;
			sumV -= v;
			sumH -= h;
			sumL -= l;
		}
		highs.push(bar.high);
		lows.push(bar.low);
		volumes.push(bar.volume);
		sumHv += bar.high * bar.volume;
		sumLv += bar.low * bar.volume;
		sumV += bar.volume;
		sumH += bar.high;
		sumL += bar.low;
		if (highs.length < period) return null;
		var n:Float = period;
		var support:Float;
		var resistance:Float;
		if (sumV > 0.0) {
			support = sumLv / sumV;
			resistance = sumHv / sumV;
		} else {
			support = sumL / n;
			resistance = sumH / n;
		}
		var out:VolumeWeightedSrOutput = {support: support, resistance: resistance};
		last = out;
		return out;
	}

	public function reset():Void {
		highs = [];
		lows = [];
		volumes = [];
		sumHv = 0.0;
		sumLv = 0.0;
		sumV = 0.0;
		sumH = 0.0;
		sumL = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "VolumeWeightedSr";

	public static function spec():IndicatorSpec {
		return {
			name: "volume_weighted_sr", args: [TWindow], ret: TObject([
				{name: "support", ty: TScalar}, {name: "resistance", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill:VolumeWeightedSrOutput = {support: Math.NaN, resistance: Math.NaN};
				return IndicatorCache.evalBar(h, "volume_weighted_sr:" + p, nanFill,
					() -> new VolumeWeightedSr(p), (i, b) -> (cast i : VolumeWeightedSr).update(b));
			}
		};
	}
}
