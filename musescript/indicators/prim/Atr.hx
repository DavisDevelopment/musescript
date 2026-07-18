package musescript.indicators.prim;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;

/**
 * Average True Range (Wilder) — ported from wickra-core's `Atr`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/atr.rs).
 *
 * True range per bar is `max(high-low, |high-prevClose|, |low-prevClose|)`
 * (the first bar, with no previous close, uses `high-low`). Seeded with the
 * simple mean of the first `period` true ranges, then Wilder smoothing
 * `avg = (avg*(n-1) + tr) / n`.
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes `atr`).
 * Reusable streaming building block for `lib/` composites Wickra builds on
 * `Atr` (Keltner, SuperTrend, ATR bands, ...).
 */
class Atr implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var nMinus1:Float;
	var invPeriod:Float;
	var hasPrevClose:Bool;
	var prevClose:Float;
	var seedBuf:Array<Float>;
	var avg:Float;
	var seeded:Bool;

	public function new(period:Int) {
		if (period <= 0) throw "Atr: period must be > 0";
		this.period = period;
		nMinus1 = period - 1.0;
		invPeriod = 1.0 / period;
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		var hl = bar.high - bar.low;
		var tr = hl;
		if (hasPrevClose) {
			var hp = Math.abs(bar.high - prevClose);
			var lp = Math.abs(bar.low - prevClose);
			tr = Math.max(hl, Math.max(hp, lp));
		}
		prevClose = bar.close;
		hasPrevClose = true;

		if (seeded) {
			avg = (avg * nMinus1 + tr) * invPeriod;
			return avg;
		}
		seedBuf.push(tr);
		if (seedBuf.length == period) {
			var sum = 0.0;
			for (v in seedBuf) sum += v;
			avg = sum / period;
			seeded = true;
			return avg;
		}
		return null;
	}

	public function reset():Void {
		hasPrevClose = false;
		prevClose = 0.0;
		seedBuf = [];
		avg = 0.0;
		seeded = false;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return seeded;
	public function name():String return "ATR";

	/** Latest value, or NaN before seeding. */
	public function value():Float return seeded ? avg : Math.NaN;
}
