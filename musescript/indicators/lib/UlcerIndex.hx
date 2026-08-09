package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Ulcer Index — ported from wickra-core's `UlcerIndex`
 * (vendor/wickra/crates/wickra-core/src/indicators/ulcer_index.rs).
 *
 * Peter Martin's downside-only volatility measure: for each bar, the
 * percentage drop from the highest price of the trailing window, squared,
 * root-mean-squared over the window:
 *
 * drawdown_t = 100 · (price_t − max(price, period)_t) / max(price, period)_t
 * UlcerIndex = √( mean( drawdown² over period ) )
 *
 * A pure up-trend never trades below its own running high, so its Ulcer
 * Index is 0. Amortised O(1) per update: the trailing maximum is tracked
 * with a monotonically-decreasing deque of `(index, price)` pairs. A
 * non-finite input is ignored (state untouched, last value returned).
 * Warmup is `2·period − 1` (max window fills, then the RMS window fills,
 * overlapping by one bar).
 */
class UlcerIndex implements MuseIndicator<Float, Float> {
	var period:Int;
	/** 1-based count of finite inputs seen so far. */
	var count:Int;
	/** Monotonically-decreasing deque of `{i, v}` over the trailing window. */
	var maxDq:Array<{i:Int, v:Float}>;
	/** Logical head into `maxDq` (expired fronts advance the head). */
	var maxDqHead:Int;
	var drawdownsSq:RingBuffer<Float>;
	var sumSq:Float;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period == 0) throw "UlcerIndex: period must be > 0";
		this.period = period;
		reset();
	}

	/** Current value if available (null before warmup). */
	public function value():Null<Float> return last;

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; state is left untouched.
			return last;
		}
		count++;
		// Drop tail entries dominated by `input` (<= and at least as old).
		while (maxDq.length > maxDqHead && maxDq[maxDq.length - 1].v <= input) maxDq.pop();
		maxDq.push({ i: count, v: input });
		// Expire the head once it falls out of the trailing window.
		var windowLo = count - (period - 1);
		if (windowLo < 0) windowLo = 0;
		while (maxDqHead < maxDq.length && maxDq[maxDqHead].i < windowLo) maxDqHead++;
		// Compact occasionally so the backing array stays bounded.
		if (maxDqHead > 0 && maxDqHead * 2 >= maxDq.length) {
			maxDq = maxDq.slice(maxDqHead);
			maxDqHead = 0;
		}
		if (count < period) return null;
		// Front is the trailing max in O(1).
		var maxPrice = maxDq[maxDqHead].v;
		var drawdown = maxPrice == 0.0 ? 0.0 : 100.0 * (input - maxPrice) / maxPrice;
		var sq = drawdown * drawdown;

		var wasFull = drawdownsSq.isFull();
		var old = drawdownsSq.push(sq);
		if (wasFull) sumSq -= old;
		sumSq += sq;
		if (drawdownsSq.length < period) return null;
		var ui = Math.sqrt(sumSq / period);
		last = ui;
		return ui;
	}

	public function reset():Void {
		count = 0;
		maxDq = [];
		maxDqHead = 0;
		drawdownsSq = new RingBuffer(period);
		sumSq = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return 2 * period - 1;
	public function isReady():Bool return last != null;
	public function name():String return "UlcerIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "ulcer_index", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "ulcer_index:" + series + ":" + p, series, Math.NaN,
					() -> new UlcerIndex(p), (i, v) -> (cast i : UlcerIndex).update(v));
			}
		};
	}
}
