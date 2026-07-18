package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** Acceleration Bands output: upper/middle/lower bands. */
typedef AccelerationBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Acceleration Bands (Price Headley) — ported from wickra-core's `AccelerationBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/acceleration_bands.rs).
 *
 * SMA-smoothed bands that widen with each bar's relative range (high − low) / (high + low).
 *
 * ratio  = (high − low) / (high + low)
 * raw_up = high · (1 + factor · ratio)
 * raw_lo = low  · (1 − factor · ratio)
 * upper  = SMA(raw_up, period)
 * middle = SMA(close,  period)
 * lower  = SMA(raw_lo, period)
 *
 * Headley's reference: period = 20, factor = 0.001.
 */
class AccelerationBands implements MuseIndicator<Bar, AccelerationBandsOutput> {
	var upperSma:Sma;
	var middleSma:Sma;
	var lowerSma:Sma;
	var factor:Float;
	var period:Int;

	public function new(period:Int, factor:Float) {
		if (period <= 0) throw "AccelerationBands: period must be > 0";
		if (!Math.isFinite(factor) || factor <= 0.0) throw "AccelerationBands: factor must be positive and finite";
		this.upperSma = new Sma(period);
		this.middleSma = new Sma(period);
		this.lowerSma = new Sma(period);
		this.factor = factor;
		this.period = period;
	}

	public function update(bar:Bar):Null<AccelerationBandsOutput> {
		// (high + low) == 0 is geometrically impossible for valid OHLC, but guard anyway.
		var sumHl = bar.high + bar.low;
		var ratio = if (sumHl == 0.0) {
			0.0;
		} else {
			(bar.high - bar.low) / sumHl;
		}
		var rawUp = bar.high * (1.0 + factor * ratio);
		var rawLo = bar.low * (1.0 - factor * ratio);

		// Feed all three SMAs unconditionally so they warm up in lock-step.
		var upper = upperSma.update(rawUp);
		var middle = middleSma.update(bar.close);
		var lower = lowerSma.update(rawLo);

		if (upper == null || middle == null || lower == null) return null;

		return {
			upper: upper,
			middle: middle,
			lower: lower
		};
	}

	public function reset():Void {
		upperSma.reset();
		middleSma.reset();
		lowerSma.reset();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return middleSma.isReady();
	public function name():String return "AccelerationBands";

	public static function spec():IndicatorSpec {
		return {
			name: "acceleration_bands", args: [TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var f = IndicatorCache.floatArg(args, 1, 0.001);
				return IndicatorCache.evalBar(h, "acceleration_bands:" + p + ":" + f,
					{ upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new AccelerationBands(p, f), (i, b) -> (cast i : AccelerationBands).update(b));
			}
		};
	}
}
