package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Pivot Reversal — ported from wickra-core's `PivotReversal`
 * (vendor/wickra/crates/wickra-core/src/indicators/pivot_reversal.rs).
 *
 * Emits a reversal breakout signal when price closes through the most
 * recently confirmed swing pivot:
 *
 *   pivot high: a bar whose high is strictly above the `left` bars before
 *               and the `right` bars after it (confirmed `right` bars late)
 *   pivot low : the mirror on lows
 *   signal = +1 when close crosses above the last confirmed pivot high
 *   signal = −1 when close crosses below the last confirmed pivot low
 *   signal =  0 otherwise
 *
 * Signals fire only on the crossing bar, not while price sits beyond the
 * level. The first signal can appear once `left + right + 1` bars exist.
 */
class PivotReversal implements MuseIndicator<Bar, Float> {
	var left:Int;
	var right:Int;
	var window:Array<Bar>;
	var pivotHighLevel:Null<Float>;
	var pivotLowLevel:Null<Float>;
	var prevClose:Null<Float>;
	var last:Null<Float>;

	public function new(left:Int, right:Int) {
		if (left <= 0 || right <= 0) throw "PivotReversal: left and right must be > 0";
		this.left = left;
		this.right = right;
		window = [];
		pivotHighLevel = null;
		pivotLowLevel = null;
		prevClose = null;
		last = null;
	}

	/** Most recent confirmed pivot-high level, if any. */
	public function pivotHigh():Null<Float> return pivotHighLevel;

	/** Most recent confirmed pivot-low level, if any. */
	public function pivotLow():Null<Float> return pivotLowLevel;

	/** Current value if available. */
	public function value():Null<Float> return last;

	public function update(candle:Bar):Null<Float> {
		var close = candle.close;
		if (window.length == left + right + 1) {
			window.shift();
		}
		window.push(candle);
		if (window.length < left + right + 1) {
			prevClose = close;
			return null;
		}

		// Confirm the pivot candidate sitting `right` bars back.
		var cand = window[left];
		var isHigh = true;
		var isLow = true;
		for (i in 0...window.length) {
			if (i == left) continue;
			if (window[i].high >= cand.high) isHigh = false;
			if (window[i].low <= cand.low) isLow = false;
		}
		if (isHigh) pivotHighLevel = cand.high;
		if (isLow) pivotLowLevel = cand.low;

		// Breakout crossing of the latest confirmed pivots by the current close.
		var signal = 0.0;
		if (pivotHighLevel != null && prevClose != null) {
			var ph:Float = pivotHighLevel;
			var pc:Float = prevClose;
			if (close > ph && pc <= ph) signal = 1.0;
		}
		if (pivotLowLevel != null && prevClose != null) {
			var pl:Float = pivotLowLevel;
			var pc:Float = prevClose;
			if (close < pl && pc >= pl) signal = -1.0;
		}
		prevClose = close;
		last = signal;
		return signal;
	}

	public function reset():Void {
		window = [];
		pivotHighLevel = null;
		pivotLowLevel = null;
		prevClose = null;
		last = null;
	}

	public function warmupPeriod():Int return left + right + 1;
	public function isReady():Bool return last != null;
	public function name():String return "PivotReversal";

	public static function spec():IndicatorSpec {
		return {
			name: "pivot_reversal", args: [TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var l = IndicatorCache.intArg(args, 0, 2);
				var r = IndicatorCache.intArg(args, 1, 2);
				return IndicatorCache.evalBar(h, "pivot_reversal:" + l + ":" + r, Math.NaN,
					() -> new PivotReversal(l, r), (i, b) -> (cast i : PivotReversal).update(b));
			}
		};
	}
}
