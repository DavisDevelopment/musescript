package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Elder SafeZone output: the long and short stop levels. */
typedef ElderSafezoneOutput = {
	var longStop:Float;
	var shortStop:Float;
}

/**
 * Elder's SafeZone stop: a volatility-aware trailing stop built from the
 * *average size of adverse penetrations* below the prior low (for a long
 * stop) or above the prior high (for a short stop), rather than a generic
 * ATR multiple — it specifically measures how far the market has recently
 * "faked out" against the position.
 *
 * downPenetration_t = max(0, low_{t-1} - low_t)
 * upPenetration_t   = max(0, high_t - high_{t-1})
 * avgDown/avgUp      = mean(penetration, period)   (including zero bars)
 * longStop  = lowestLow(period) - coefficient * avgDownPenetration
 * shortStop = highestHigh(period) + coefficient * avgUpPenetration
 */
class ElderSafezone implements MuseIndicator<Bar, ElderSafezoneOutput> {
	var period:Int;
	var coefficient:Float;
	var hasPrev:Bool;
	var prevHigh:Float;
	var prevLow:Float;
	var downPenetrations:Array<Float>;
	var upPenetrations:Array<Float>;
	var sumDown:Float;
	var sumUp:Float;
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new(period:Int, coefficient:Float) {
		if (period <= 0) throw "ElderSafezone: period must be > 0";
		if (!Math.isFinite(coefficient) || coefficient <= 0.0) throw "ElderSafezone: coefficient must be positive and finite";
		this.period = period;
		this.coefficient = coefficient;
		hasPrev = false;
		prevHigh = 0.0;
		prevLow = 0.0;
		downPenetrations = [];
		upPenetrations = [];
		sumDown = 0.0;
		sumUp = 0.0;
		highs = [];
		lows = [];
	}

	public function update(bar:Bar):Null<ElderSafezoneOutput> {
		if (highs.length == period) highs.shift();
		highs.push(bar.high);
		if (lows.length == period) lows.shift();
		lows.push(bar.low);

		if (hasPrev) {
			var down = Math.max(0.0, prevLow - bar.low);
			var up = Math.max(0.0, bar.high - prevHigh);
			if (downPenetrations.length == period) sumDown -= downPenetrations.shift();
			downPenetrations.push(down);
			sumDown += down;
			if (upPenetrations.length == period) sumUp -= upPenetrations.shift();
			upPenetrations.push(up);
			sumUp += up;
		}
		prevHigh = bar.high;
		prevLow = bar.low;
		hasPrev = true;

		if (highs.length < period || downPenetrations.length < period) return null;

		var hh = highs[0];
		for (v in highs) if (v > hh) hh = v;
		var ll = lows[0];
		for (v in lows) if (v < ll) ll = v;

		var avgDown = sumDown / period;
		var avgUp = sumUp / period;
		return { longStop: ll - coefficient * avgDown, shortStop: hh + coefficient * avgUp };
	}

	public function reset():Void {
		hasPrev = false;
		prevHigh = 0.0;
		prevLow = 0.0;
		downPenetrations = [];
		upPenetrations = [];
		sumDown = 0.0;
		sumUp = 0.0;
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return downPenetrations.length == period;
	public function name():String return "ElderSafezone";

	public static function spec():IndicatorSpec {
		return {
			name: "elder_safezone", args: [TWindow, TScalar], ret: TObject([
				{name: "longStop", ty: TScalar}, {name: "shortStop", ty: TScalar}
			]), minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				var coef = IndicatorCache.floatArg(args, 1, 2.5);
				var key = "elder_safezone:" + p + ":" + coef;
				return IndicatorCache.evalBar(h, key, { longStop: Math.NaN, shortStop: Math.NaN },
					() -> new ElderSafezone(p, coef), (i, b) -> (cast i : ElderSafezone).update(b));
			}
		};
	}
}
