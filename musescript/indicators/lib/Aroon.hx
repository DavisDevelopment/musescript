package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** Aroon output: up/down strengths in [0, 100]. */
typedef AroonOutput = {
	var up:Float;
	var down:Float;
}

/**
 * Aroon Up/Down — ported from wickra-core's `Aroon`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/aroon.rs).
 *
 * Tracks how many bars since the highest high and lowest low inside a
 * `period + 1`-bar window, expressed as a percentage of the window.
 */
class Aroon implements MuseIndicator<Bar, AroonOutput> {
	var period:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Aroon: period must be > 0";
		this.period = period;
		highs = new RingBuffer(period + 1);
		lows = new RingBuffer(period + 1);
	}

	public function update(bar:Bar):Null<AroonOutput> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < period + 1) return null;
		var hhIdx = 0, llIdx = 0;
		var hh = Math.NEGATIVE_INFINITY, ll = Math.POSITIVE_INFINITY;
		// `oldest(i)` preserves Array window index order (oldest-first).
		for (i in 0...highs.length) {
			var h = highs.oldest(i);
			var l = lows.oldest(i);
			if (h >= hh) { hh = h; hhIdx = i; }
			if (l <= ll) { ll = l; llIdx = i; }
		}
		var n:Float = period;
		return { up: 100.0 * hhIdx / n, down: 100.0 * llIdx / n };
	}

	public function reset():Void {
		highs = new RingBuffer(period + 1);
		lows = new RingBuffer(period + 1);
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return highs.length == period + 1;
	public function name():String return "Aroon";

	public static function spec():IndicatorSpec {
		return {
			name: "aroon", args: [TWindow], ret: TObject([
				{name: "up", ty: TScalar}, {name: "down", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "aroon:" + p, { up: Math.NaN, down: Math.NaN },
					() -> new Aroon(p), (i, b) -> (cast i : Aroon).update(b));
			}
		};
	}
}
