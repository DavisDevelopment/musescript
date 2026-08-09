package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Stochastic Momentum Index — ported from wickra-core's `Smi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/smi.rs).
 *
 * Over the lookback `period`, with HH = max(high), LL = min(low),
 * C = (HH + LL) / 2 and R = HH - LL, the raw displacement d = close - C.
 * Both d and R are smoothed twice with EMAs:
 *
 *   D_smoothed  = EMA(EMA(d, dPeriod), d2Period)
 *   HL_smoothed = EMA(EMA(R, dPeriod), d2Period)
 *   SMI         = 100 * D_smoothed / (HL_smoothed / 2)
 *
 * Blau's recommended defaults are (period = 5, d = 3, d2 = 3). A window
 * where the smoothed range collapses to zero holds the previous reading
 * rather than emitting infinity.
 */
class Smi implements MuseIndicator<Bar, Float> {
	var period:Int;
	var dPeriod:Int;
	var d2Period:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var emaD1:Ema;
	var emaD2:Ema;
	var emaR1:Ema;
	var emaR2:Ema;
	var current:Null<Float>;

	public function new(period:Int, dPeriod:Int, d2Period:Int) {
		if (period <= 0 || dPeriod <= 0 || d2Period <= 0) throw "Smi: periods must be > 0";
		this.period = period;
		this.dPeriod = dPeriod;
		this.d2Period = d2Period;
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		emaD1 = new Ema(dPeriod);
		emaD2 = new Ema(d2Period);
		emaR1 = new Ema(dPeriod);
		emaR2 = new Ema(d2Period);
		current = null;
	}

	/** Blau's recommended defaults (period = 5, d = 3, d2 = 3). */
	public static function classic():Smi return new Smi(5, 3, 3);

	/** Configured (period, dPeriod, d2Period). */
	public function periods():{period:Int, dPeriod:Int, d2Period:Int}
		return {period: period, dPeriod: dPeriod, d2Period: d2Period};

	public function update(bar:Bar):Null<Float> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < period) return null;
		var hh = Math.NEGATIVE_INFINITY;
		var ll = Math.POSITIVE_INFINITY;
		for (i in 0...highs.length) {
			var h = highs.at(i);
			var l = lows.at(i);
			if (h > hh) hh = h;
			if (l < ll) ll = l;
		}
		var center = (hh + ll) / 2.0;
		var displacement = bar.close - center;
		var range = hh - ll;

		// Feed every EMA on every candle so both stacks warm in parallel —
		// gating the range stack behind the displacement stack would starve
		// it by one input.
		var d1 = emaD1.update(displacement);
		var r1 = emaR1.update(range);
		var d2 = d1 != null ? emaD2.update(d1) : null;
		var r2 = r1 != null ? emaR2.update(r1) : null;
		if (d2 == null || r2 == null) return null;

		if (r2 <= 0.0) {
			// Window where the smoothed range collapses to zero: the formula
			// is undefined. Hold the previous reading rather than emit inf.
			return current;
		}
		var value = 100.0 * d2 / (r2 / 2.0);
		current = value;
		return value;
	}

	public function reset():Void {
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		emaD1.reset();
		emaD2.reset();
		emaR1.reset();
		emaR2.reset();
		current = null;
	}

	public function warmupPeriod():Int return period + dPeriod + d2Period - 2;
	public function isReady():Bool return current != null;
	public function name():String return "SMI";

	public static function spec():IndicatorSpec {
		return {
			name: "smi", args: [TWindow, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 5);
				var d = IndicatorCache.intArg(args, 1, 3);
				var d2 = IndicatorCache.intArg(args, 2, 3);
				return IndicatorCache.evalBar(h, "smi:" + p + ":" + d + ":" + d2, Math.NaN,
					() -> new Smi(p, d, d2), (i, b) -> (cast i : Smi).update(b));
			}
		};
	}
}
