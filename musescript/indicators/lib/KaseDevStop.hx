package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Kase DevStop output: the active trailing-stop level and the direction it protects. */
typedef KaseDevStopOutput = {
	/** The DevStop level — below price in an uptrend, above price in a downtrend. */
	var value:Float;
	/** Trend direction: +1.0 long (stop below price), -1.0 short. */
	var direction:Float;
}

/**
 * Kase DevStop — ported from wickra-core's `KaseDevStop`
 * (vendor/wickra/crates/wickra-core/src/indicators/kase_devstop.rs).
 *
 * Cynthia Kase's volatility stop, built on the standard deviation of the
 * TWO-BAR true range rather than a single-bar ATR:
 *
 *   DTR_t = max(high_t, high_{t−1}) − min(low_t, low_{t−1})
 *   band  = mean(DTR, period) + dev · sampleStddev(DTR, period)
 *   long  stop = ratchet_up(highest_high_since_flip − band)
 *   short stop = ratchet_down(lowest_low_since_flip + band)
 *
 * The stop trails the extreme reached since the last reversal — ratcheting
 * only in the trend's favour — and flips sides when price closes through it.
 * The first bar seeds the prior candle; the first stop lands after
 * `period + 1` inputs.
 */
class KaseDevStop implements MuseIndicator<Bar, KaseDevStopOutput> {
	var period:Int;
	var dev:Float;
	var hasPrev:Bool;
	var prevHigh:Float;
	var prevLow:Float;
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;
	var direction:Float;
	var extreme:Float;
	var stop:Float;
	var last:Null<KaseDevStopOutput>;

	public function new(period:Int, dev:Float) {
		if (period < 2) throw "KaseDevStop: period must be >= 2";
		if (!Math.isFinite(dev) || dev <= 0.0) throw "KaseDevStop: dev must be positive and finite";
		this.period = period;
		this.dev = dev;
		reset();
	}

	/** Sample standard deviation from a running (sum, sum of squares, count). */
	static function sampleStddev(sum:Float, sumSq:Float, count:Int):Float {
		var n:Float = count;
		var mean = sum / n;
		return Math.sqrt(Math.max((sumSq - n * mean * mean) / (n - 1.0), 0.0));
	}

	public function update(bar:Bar):Null<KaseDevStopOutput> {
		if (!hasPrev) {
			hasPrev = true;
			prevHigh = bar.high;
			prevLow = bar.low;
			return null;
		}
		var dtr = Math.max(bar.high, prevHigh) - Math.min(bar.low, prevLow);
		prevHigh = bar.high;
		prevLow = bar.low;

		if (window.length == period) {
			var old = window.shift();
			sum -= old;
			sumSq -= old * old;
		}
		window.push(dtr);
		sum += dtr;
		sumSq += dtr * dtr;
		if (window.length < period) return null;

		var mean = sum / period;
		var band = mean + dev * sampleStddev(sum, sumSq, period);

		if (direction == 0.0) {
			// Seed the trend as long off the first fully-warmed bar.
			direction = 1.0;
			extreme = bar.high;
			stop = bar.high - band;
		} else if (direction > 0.0) {
			extreme = Math.max(extreme, bar.high);
			var raw = extreme - band;
			stop = Math.max(stop, raw);
			if (bar.close < stop) {
				direction = -1.0;
				extreme = bar.low;
				stop = bar.low + band;
			}
		} else {
			extreme = Math.min(extreme, bar.low);
			var raw = extreme + band;
			stop = Math.min(stop, raw);
			if (bar.close > stop) {
				direction = 1.0;
				extreme = bar.high;
				stop = bar.high - band;
			}
		}

		var out = {value: stop, direction: direction};
		last = out;
		return out;
	}

	public function reset():Void {
		hasPrev = false;
		prevHigh = 0.0;
		prevLow = 0.0;
		window = [];
		sum = 0.0;
		sumSq = 0.0;
		direction = 0.0;
		extreme = 0.0;
		stop = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "KaseDevStop";

	public static function spec():IndicatorSpec {
		return {
			name: "kase_devstop", args: [TWindow, TScalar], ret: TObject([
				{name: "value", ty: TScalar}, {name: "direction", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 30);
				var d = IndicatorCache.floatArg(args, 1, 1.0);
				var key = "kase_devstop:" + p + ":" + d;
				return IndicatorCache.evalBar(h, key, {value: Math.NaN, direction: Math.NaN},
					() -> new KaseDevStop(p, d), (i, b) -> (cast i : KaseDevStop).update(b));
			}
		};
	}
}
