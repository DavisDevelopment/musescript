package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** SuperTrend output: the trailing-stop level and the trend direction. */
typedef SuperTrendOutput = {
	/** The SuperTrend line — the active trailing-stop level for this bar. */
	var value:Float;
	/** Trend direction: +1.0 in an uptrend (line below price), -1.0 in a downtrend. */
	var direction:Float;
}

/**
 * SuperTrend — ported from wickra-core's `SuperTrend`
 * (vendor/wickra/crates/wickra-core/src/indicators/super_trend.rs).
 *
 * An ATR-banded trailing stop that flips sides on a close through the band:
 *
 *   hl2         = (high + low) / 2
 *   basicUpper  = hl2 + multiplier · ATR
 *   basicLower  = hl2 − multiplier · ATR
 *
 * The final bands ratchet — the upper band only moves down (and the lower
 * band only moves up) until price closes through it, which flips the trend
 * and hands the role of trailing stop to the opposite band. The first
 * ATR-ready bar seeds the trend as up. Classic config is ATR(10) × 3.0.
 */
class SuperTrend implements MuseIndicator<Bar, SuperTrendOutput> {
	var atr:Atr;
	var multiplier:Float;
	var atrPeriod:Int;
	var hasPrev:Bool;
	var prevFinalUpper:Float;
	var prevFinalLower:Float;
	var prevClose:Float;
	var prevDirection:Float;

	public function new(atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "SuperTrend: multiplier must be positive and finite";
		atr = new Atr(atrPeriod);
		this.multiplier = multiplier;
		this.atrPeriod = atrPeriod;
		hasPrev = false;
		prevFinalUpper = Math.NaN;
		prevFinalLower = Math.NaN;
		prevClose = Math.NaN;
		prevDirection = 0.0;
	}

	/** Wilder's classic configuration: ATR(10) with a 3.0 multiplier. */
	public static function classic():SuperTrend {
		return new SuperTrend(10, 3.0);
	}

	public function update(bar:Bar):Null<SuperTrendOutput> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;
		var hl2 = (bar.high + bar.low) / 2.0;
		var basicUpper = hl2 + multiplier * atrVal;
		var basicLower = hl2 - multiplier * atrVal;

		var finalUpper:Float;
		var finalLower:Float;
		var direction:Float;
		if (!hasPrev) {
			// First ATR-ready bar: no prior bands, seed the trend as up.
			finalUpper = basicUpper;
			finalLower = basicLower;
			direction = 1.0;
		} else {
			finalUpper = (basicUpper < prevFinalUpper || prevClose > prevFinalUpper) ? basicUpper : prevFinalUpper;
			finalLower = (basicLower > prevFinalLower || prevClose < prevFinalLower) ? basicLower : prevFinalLower;
			if (prevDirection < 0.0) {
				// Previous downtrend — the line was the upper band.
				direction = bar.close <= finalUpper ? -1.0 : 1.0;
			} else {
				// Previous uptrend — the line was the lower band.
				direction = bar.close >= finalLower ? 1.0 : -1.0;
			}
		}

		var value = direction > 0.0 ? finalLower : finalUpper;
		hasPrev = true;
		prevFinalUpper = finalUpper;
		prevFinalLower = finalLower;
		prevClose = bar.close;
		prevDirection = direction;
		return {value: value, direction: direction};
	}

	public function reset():Void {
		atr.reset();
		hasPrev = false;
	}

	public function warmupPeriod():Int return atrPeriod;
	public function isReady():Bool return hasPrev;
	public function name():String return "SuperTrend";

	public static function spec():IndicatorSpec {
		return {
			name: "super_trend", args: [TWindow, TScalar], ret: TObject([
				{name: "value", ty: TScalar}, {name: "direction", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				var m = IndicatorCache.floatArg(args, 1, 3.0);
				var key = "super_trend:" + p + ":" + m;
				return IndicatorCache.evalBar(h, key, {value: Math.NaN, direction: Math.NaN},
					() -> new SuperTrend(p, m), (i, b) -> (cast i : SuperTrend).update(b));
			}
		};
	}
}
