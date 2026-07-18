package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Relative Strength Index (Wilder) — ported from wickra-core's `Rsi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rsi.rs).
 *
 * Wilder smoothing (`alpha = 1/period`): the first bar seeds the previous
 * close (no change yet); the next `period` gains/losses are simple-averaged
 * to seed avg_gain/avg_loss; thereafter `avg = (avg*(n-1) + x) / n`. Final
 * value `100*avg_gain / (avg_gain + avg_loss)`, with the both-zero (flat)
 * case returning the neutral 50. First value emits at bar `period` (i.e.
 * after `period + 1` inputs).
 *
 * A `prim/` PRIMITIVE, not a builtin: MuseScript already exposes its own
 * `rsi` (a rolling-window, NON-Wilder variant — deliberately not replaced,
 * corpus/parity tests depend on it). This faithful Wilder port is the
 * reusable streaming building block for `lib/` composites Wickra builds on
 * `Rsi` (Stoch-RSI, Connors RSI, etc.). Migrating the builtin `rsi` to this
 * Wilder-correct version is a separate, tracked decision (ROADMAP.md epic 9).
 */
class Rsi implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var nMinus1:Float;
	var invPeriod:Float;
	var prevClose:Float;
	var hasPrev:Bool;
	var seedGains:Array<Float>;
	var seedLosses:Array<Float>;
	var avgGain:Float;
	var avgLoss:Float;
	var avgsSeeded:Bool;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Rsi: period must be > 0";
		this.period = period;
		nMinus1 = period - 1.0;
		invPeriod = 1.0 / period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return lastValue;
		if (!hasPrev) {
			prevClose = input;
			hasPrev = true;
			return null;
		}
		var prev = prevClose;
		prevClose = input;
		var diff = input - prev;
		var gain = diff > 0 ? diff : 0.0;
		var loss = diff < 0 ? -diff : 0.0;

		if (avgsSeeded) {
			avgGain = (avgGain * nMinus1 + gain) * invPeriod;
			avgLoss = (avgLoss * nMinus1 + loss) * invPeriod;
			var v = rsiFromAvgs(avgGain, avgLoss);
			lastValue = v;
			return v;
		}

		seedGains.push(gain);
		seedLosses.push(loss);
		if (seedGains.length == period) {
			var sg = 0.0, sl = 0.0;
			for (x in seedGains) sg += x;
			for (x in seedLosses) sl += x;
			avgGain = sg / period;
			avgLoss = sl / period;
			avgsSeeded = true;
			var v = rsiFromAvgs(avgGain, avgLoss);
			lastValue = v;
			return v;
		}
		return null;
	}

	static inline function rsiFromAvgs(ag:Float, al:Float):Float {
		var denom = ag + al;
		return denom == 0 ? 50.0 : 100.0 * ag / denom;
	}

	public function reset():Void {
		prevClose = 0.0;
		hasPrev = false;
		seedGains = [];
		seedLosses = [];
		avgGain = 0.0;
		avgLoss = 0.0;
		avgsSeeded = false;
		lastValue = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return avgsSeeded;
	public function name():String return "RSI";

	/** Latest value, or NaN before seeding. */
	public function value():Float return lastValue != null ? lastValue : Math.NaN;
}
