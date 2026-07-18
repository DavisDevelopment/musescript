package musescript.indicators;

import musescript.harness.Bar;

/**
 * On-Balance Volume — ported from wickra-core's `Obv`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/obv.rs).
 *
 * A cumulative signed-volume series: each bar adds +volume, -volume, or 0
 * depending on whether its close is above, below, or equal to the previous
 * close. The first value (after the first bar) is conventionally 0.
 */
class Obv implements MuseIndicator<Bar, Float> {
	var hasPrev:Bool;
	var prevClose:Float;
	var total:Float;
	var hasEmitted:Bool;

	public function new() {
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		if (hasPrev) {
			if (bar.close > prevClose) total += bar.volume;
			else if (bar.close < prevClose) total -= bar.volume;
		}
		prevClose = bar.close;
		hasPrev = true;
		hasEmitted = true;
		return total;
	}

	public function reset():Void {
		hasPrev = false;
		prevClose = 0.0;
		total = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "OBV";
}
