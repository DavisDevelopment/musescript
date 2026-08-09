package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** Random Walk Index output: the bullish (high) and bearish (low) lines. */
typedef RwiOutput = {
	var high:Float;
	var low:Float;
}

/**
 * Random Walk Index (Mike Poulos) — ported from wickra-core's `Rwi`
 * (vendor/wickra/crates/wickra-core/src/indicators/rwi.rs).
 *
 * For each lookback i ∈ [2, period]:
 *
 *   RWI_High_t(i) = (high_t − low_{t-i+1}) / (ATR_i(t) * sqrt(i))
 *   RWI_Low_t(i)  = (high_{t-i+1} − low_t) / (ATR_i(t) * sqrt(i))
 *
 * where ATR_i(t) is the simple mean of the i−1 true ranges between those
 * bars. The reported lines are the maxima across all lookbacks. First output
 * after `period` candles; a zero-ATR lookback is skipped.
 */
class Rwi implements MuseIndicator<Bar, RwiOutput> {
	var period:Int;
	/** Rolling window of the most recent `period` candles (oldest first). */
	var candles:RingBuffer<Bar>;
	/** Rolling window of true ranges; trs[k] = TR of candles[k+1] vs candles[k]. */
	var trs:RingBuffer<Float>;
	var last:Null<RwiOutput>;

	public function new(period:Int) {
		if (period <= 0) throw "Rwi: period must be > 0";
		if (period < 2) throw "Rwi: RWI requires period >= 2";
		this.period = period;
		reset();
	}

	public function update(candle:Bar):Null<RwiOutput> {
		// True range of this candle vs. the previous close (if any).
		var tr:Float;
		if (candles.length > 0) {
			var prev = candles.at(0); // newest retained so far
			var hl = candle.high - candle.low;
			var hc = Math.abs(candle.high - prev.close);
			var lc = Math.abs(candle.low - prev.close);
			tr = Math.max(hl, Math.max(hc, lc));
		} else {
			tr = candle.high - candle.low;
		}

		candles.push(candle);

		// `trs` aligns with `candles` from index 1 onward.
		if (candles.length >= 2) {
			trs.push(tr);
		}

		if (candles.length < period) return null;

		var n = candles.length; // == period
		var lastHigh = candles.oldest(n - 1).high;
		var lastLow = candles.oldest(n - 1).low;

		var rwiHigh = 0.0;
		var rwiLow = 0.0;
		// For lookback i in [2, period]: compare bar n-1 to bar n-i, over the
		// i-1 true ranges between them (strictly causal ATR).
		for (i in 2...(period + 1)) {
			var trStart = n - i;
			var trEnd = n - 1;
			var count = trEnd - trStart;
			var sum = 0.0;
			for (k in trStart...trEnd) sum += trs.oldest(k);
			var atrI = sum / count;
			var denom = atrI * Math.sqrt(i);
			if (denom == 0.0) continue;
			var oldLow = candles.oldest(n - i).low;
			var oldHigh = candles.oldest(n - i).high;
			var hv = (lastHigh - oldLow) / denom;
			var lv = (oldHigh - lastLow) / denom;
			if (hv > rwiHigh) rwiHigh = hv;
			if (lv > rwiLow) rwiLow = lv;
		}

		var out:RwiOutput = { high: rwiHigh, low: rwiLow };
		last = out;
		return out;
	}

	public function reset():Void {
		candles = new RingBuffer(period);
		trs = new RingBuffer(period - 1);
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "RWI";

	public static function spec():IndicatorSpec {
		return {
			name: "rwi", args: [TWindow], ret: TObject([
				{name: "high", ty: TScalar}, {name: "low", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var nanFill = { high: Math.NaN, low: Math.NaN };
				return IndicatorCache.evalBar(h, "rwi:" + p, nanFill,
					() -> new Rwi(p), (i, b) -> (cast i : Rwi).update(b));
			}
		};
	}
}
