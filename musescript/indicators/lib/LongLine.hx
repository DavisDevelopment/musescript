package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Long Line candlestick pattern — a bar whose body is unusually large
 * relative to the recent average body size, signalling a decisive move.
 *
 * avgBody = mean(|close - open|, period)   (over the PRIOR `period` bars,
 *           excluding the current one — so a bar can't inflate its own
 *           baseline)
 *
 * output: +1.0 if green and body > multiplier * avgBody
 *         -1.0 if red and body > multiplier * avgBody
 *          0.0 otherwise (including while the baseline window warms up)
 */
class LongLine implements MuseIndicator<Bar, Float> {
	var period:Int;
	var multiplier:Float;
	var bodyWindow:RingBuffer<Float>;
	var sum:Float;

	public function new(period:Int, multiplier:Float) {
		if (period <= 0) throw "LongLine: period must be > 0";
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "LongLine: multiplier must be positive and finite";
		this.period = period;
		this.multiplier = multiplier;
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		var body = Math.abs(bar.close - bar.open);
		var result = 0.0;

		if (bodyWindow.isFull()) {
			var avgBody = sum / period;
			if (body > multiplier * avgBody) {
				if (bar.close > bar.open) result = 1.0;
				else if (bar.close < bar.open) result = -1.0;
			}
		}

		var wasFull = bodyWindow.isFull();
		var old = bodyWindow.push(body);
		if (wasFull) sum -= old;
		sum += body;

		return result;
	}

	public function reset():Void {
		bodyWindow = new RingBuffer(period);
		sum = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return bodyWindow.length == period;
	public function name():String return "LongLine";

	public static function spec():IndicatorSpec {
		return {
			name: "long_line", args: [TWindow, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = args.length > 0 ? IndicatorCache.intArg(args, 0, 10) : 10;
				var m = IndicatorCache.floatArg(args, 1, 1.5);
				return IndicatorCache.evalBar(h, "long_line:" + p + ":" + m, Math.NaN,
					() -> new LongLine(p, m), (i, b) -> (cast i : LongLine).update(b));
			}
		};
	}
}
