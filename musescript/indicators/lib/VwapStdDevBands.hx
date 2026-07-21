package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** VWAP StdDev Bands output. */
typedef VwapStdDevBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
	var stddev:Float;
}

/**
 * VWAP Standard-Deviation Bands — ported from wickra-core's `VwapStdDevBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/vwap_stddev_bands.rs).
 *
 *   tp_i        = (high + low + close) / 3
 *   vwap        = sum(tp*v) / sum(v)
 *   variance    = sum(tp^2*v) / sum(v) - vwap^2       (volume-weighted population)
 *   sigma       = sqrt(max(variance, 0))
 *   upper/lower = vwap ± multiplier * sigma
 *
 * Cumulative running sums make every update O(1). Zero cumulative volume
 * returns null (the volume-weighted average is undefined).
 */
class VwapStdDevBands implements MuseIndicator<Bar, VwapStdDevBandsOutput> {
	public var multiplier(default, null):Float;
	var sumPv:Float;
	var sumP2v:Float;
	var sumV:Float;
	var hasEmitted:Bool;

	public function new(multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0)
			throw "VwapStdDevBands: multiplier must be finite and strictly positive";
		this.multiplier = multiplier;
		sumPv = 0.0;
		sumP2v = 0.0;
		sumV = 0.0;
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<VwapStdDevBandsOutput> {
		var tp = (bar.high + bar.low + bar.close) / 3.0;
		sumPv += tp * bar.volume;
		sumP2v += tp * tp * bar.volume;
		sumV += bar.volume;
		if (sumV == 0.0) return null;
		hasEmitted = true;
		var vwap = sumPv / sumV;
		// Volume-weighted population variance; clamp tiny negative cancellation
		// noise back to zero on near-constant inputs.
		var variance = Math.max(sumP2v / sumV - vwap * vwap, 0.0);
		var sigma = Math.sqrt(variance);
		return {
			upper: vwap + multiplier * sigma,
			middle: vwap,
			lower: vwap - multiplier * sigma,
			stddev: sigma
		};
	}

	public function reset():Void {
		sumPv = 0.0;
		sumP2v = 0.0;
		sumV = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "VwapStdDevBands";

	public static function spec():IndicatorSpec {
		return {
			name: "vwap_stddev_bands", args: [TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar},
				{name: "lower", ty: TScalar}, {name: "stddev", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var m = IndicatorCache.floatArg(args, 0, 2.0);
				var nanFill:VwapStdDevBandsOutput = {upper: Math.NaN, middle: Math.NaN, lower: Math.NaN, stddev: Math.NaN};
				return IndicatorCache.evalBar(h, "vwap_stddev_bands:" + m, nanFill,
					() -> new VwapStdDevBands(m), (i, b) -> (cast i : VwapStdDevBands).update(b));
			}
		};
	}
}
