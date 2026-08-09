package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
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
	var downPenetrations:RingBuffer<Float>;
	var upPenetrations:RingBuffer<Float>;
	var sumDown:Float;
	var sumUp:Float;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;

	public function new(period:Int, coefficient:Float) {
		if (period <= 0) throw "ElderSafezone: period must be > 0";
		if (!Math.isFinite(coefficient) || coefficient <= 0.0) throw "ElderSafezone: coefficient must be positive and finite";
		this.period = period;
		this.coefficient = coefficient;
		reset();
	}

	public function update(bar:Bar):Null<ElderSafezoneOutput> {
		highs.push(bar.high);
		lows.push(bar.low);

		if (hasPrev) {
			var down = Math.max(0.0, prevLow - bar.low);
			var up = Math.max(0.0, bar.high - prevHigh);
			var wasFullDown = downPenetrations.isFull();
			var oldDown = downPenetrations.push(down);
			if (wasFullDown) sumDown -= oldDown;
			sumDown += down;
			var wasFullUp = upPenetrations.isFull();
			var oldUp = upPenetrations.push(up);
			if (wasFullUp) sumUp -= oldUp;
			sumUp += up;
		}
		prevHigh = bar.high;
		prevLow = bar.low;
		hasPrev = true;

		if (highs.length < period || downPenetrations.length < period) return null;

		var hh = highs.oldest(0);
		for (i in 1...highs.length) {
			var v = highs.oldest(i);
			if (v > hh) hh = v;
		}
		var ll = lows.oldest(0);
		for (i in 1...lows.length) {
			var v = lows.oldest(i);
			if (v < ll) ll = v;
		}

		var avgDown = sumDown / period;
		var avgUp = sumUp / period;
		return { longStop: ll - coefficient * avgDown, shortStop: hh + coefficient * avgUp };
	}

	public function reset():Void {
		hasPrev = false;
		prevHigh = 0.0;
		prevLow = 0.0;
		downPenetrations = new RingBuffer(period);
		upPenetrations = new RingBuffer(period);
		sumDown = 0.0;
		sumUp = 0.0;
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
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
