package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Williams Fractals output for one bar. Each field is non-null when a
 * fractal high/low was confirmed at the CENTRE of the most recent five-bar
 * window (mirrors the Rust `Option<f64>` fields). Up and down fractals are
 * independent and can coincide.
 */
typedef WilliamsFractalsOutput = {
	var up:Null<Float>;
	var down:Null<Float>;
}

/**
 * Williams Fractals — ported from wickra-core's `WilliamsFractals`
 * (vendor/wickra/crates/wickra-core/src/indicators/williams_fractals.rs).
 *
 * Five-bar swing detector with RingBuffer windows (no Array.shift).
 * Confirmation lags by two bars. See also geom.FractalSwingAdapter for
 * PivotPoint / SwingGraph integration.
 */
class WilliamsFractals implements MuseIndicator<Bar, WilliamsFractalsOutput> {
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var out:WilliamsFractalsOutput;

	public function new() {
		highs = new RingBuffer(5);
		lows = new RingBuffer(5);
		out = { up: null, down: null };
	}

	public function update(candle:Bar):Null<WilliamsFractalsOutput> {
		highs.push(candle.high);
		lows.push(candle.low);
		if (highs.length < 5) return null;

		// RingBuffer.at(i): 0 = newest. Five-bar chronological order oldest→newest
		// is at(4), at(3), at(2), at(1), at(0). Centre = at(2).
		var h0 = highs.at(4);
		var h1 = highs.at(3);
		var h2 = highs.at(2);
		var h3 = highs.at(1);
		var h4 = highs.at(0);
		var l0 = lows.at(4);
		var l1 = lows.at(3);
		var l2 = lows.at(2);
		var l3 = lows.at(1);
		var l4 = lows.at(0);

		out.up = (h2 > h0 && h2 > h1 && h2 > h3 && h2 > h4) ? h2 : null;
		out.down = (l2 < l0 && l2 < l1 && l2 < l3 && l2 < l4) ? l2 : null;
		return out;
	}

	public function reset():Void {
		highs = new RingBuffer(5);
		lows = new RingBuffer(5);
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return highs.length == 5;
	public function name():String return "WilliamsFractals";

	public static function spec():IndicatorSpec {
		return {
			name: "williams_fractals", args: [], ret: TObject([
				{name: "up", ty: TScalar}, {name: "down", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { up: Math.NaN, down: Math.NaN };
				return IndicatorCache.evalBar(h, "williams_fractals", nanFill,
					() -> new WilliamsFractals(), function(i, b) {
						var o = (cast i : WilliamsFractals).update(b);
						if (o == null) return null;
						return {
							up: o.up == null ? Math.NaN : o.up,
							down: o.down == null ? Math.NaN : o.down
						};
					});
			}
		};
	}
}
