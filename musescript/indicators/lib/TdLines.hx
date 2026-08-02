package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Output of `TdLines`: the latest TDST resistance / support pair.
 * `resistance` is set after a completed buy setup (highest high of the setup
 * bars); `support` after a completed sell setup (lowest low). Either field is
 * NaN until the first setup in that direction completes.
 */
typedef TdLinesOutput = {
	var resistance:Float;
	var support:Float;
}

/**
 * Tom DeMark TD Lines (TDST) — ported from wickra-core's `TdLines`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_lines.rs).
 *
 * Setup-derived horizontal support / resistance: once a TD Setup completes
 * in either direction, TDST resistance is the highest high among the bars of
 * the most-recently-completed buy setup, and TDST support is the lowest low
 * among the bars of the most-recently-completed sell setup. Levels persist
 * until the next completed setup in that direction updates them. Tracks both
 * buy and sell setup state machines in parallel (the setup counting logic is
 * inlined here, mirroring the Rust source — no dependency on td_setup).
 */
class TdLines implements MuseIndicator<Bar, TdLinesOutput> {
	var lookback:Int;
	var target:Int;
	var closes:RingBuffer<Float>;
	var buyCount:Int;
	var sellCount:Int;
	/** Highest high observed during the current buy-setup run. */
	var buyRunMaxHigh:Float;
	/** Lowest low observed during the current sell-setup run. */
	var sellRunMinLow:Float;
	var resistance:Float;
	var support:Float;
	var ready:Bool;

	public function new(lookback:Int, target:Int) {
		if (lookback <= 0 || target <= 0) throw "TdLines: lookback and target must be > 0";
		this.lookback = lookback;
		this.target = target;
		reset();
	}

	/** DeMark's classic configuration: lookback = 4, target = 9. */
	public static function classic():TdLines return new TdLines(4, 9);

	/** Configured (lookback, target). */
	public function params():{lookback:Int, target:Int} return {lookback: lookback, target: target};

	public function update(bar:Bar):Null<TdLinesOutput> {
		if (closes.length < lookback) {
			closes.push(bar.close);
			return null;
		}
		var reference = closes.oldest(0);
		closes.push(bar.close);

		if (bar.close < reference) {
			// Continue / start a buy-setup run; a break of the sell run here
			// resets its running extreme.
			if (buyCount == 0) buyRunMaxHigh = bar.high;
			else buyRunMaxHigh = Math.max(buyRunMaxHigh, bar.high);
			buyCount = buyCount + 1 > target ? target : buyCount + 1;
			sellCount = 0;
			sellRunMinLow = Math.POSITIVE_INFINITY;
			if (buyCount == target) resistance = buyRunMaxHigh;
		} else if (bar.close > reference) {
			if (sellCount == 0) sellRunMinLow = bar.low;
			else sellRunMinLow = Math.min(sellRunMinLow, bar.low);
			sellCount = sellCount + 1 > target ? target : sellCount + 1;
			buyCount = 0;
			buyRunMaxHigh = Math.NEGATIVE_INFINITY;
			if (sellCount == target) support = sellRunMinLow;
		} else {
			// Equality breaks both runs.
			buyCount = 0;
			sellCount = 0;
			buyRunMaxHigh = Math.NEGATIVE_INFINITY;
			sellRunMinLow = Math.POSITIVE_INFINITY;
		}

		ready = true;
		return {resistance: resistance, support: support};
	}

	public function reset():Void {
		closes = new RingBuffer(lookback);
		buyCount = 0;
		sellCount = 0;
		buyRunMaxHigh = Math.NEGATIVE_INFINITY;
		sellRunMinLow = Math.POSITIVE_INFINITY;
		resistance = Math.NaN;
		support = Math.NaN;
		ready = false;
	}

	public function warmupPeriod():Int return lookback + 1;
	public function isReady():Bool return ready;
	public function name():String return "TDLines";

	public static function spec():IndicatorSpec {
		return {
			name: "td_lines", args: [TWindow, TWindow], ret: TObject([
				{name: "resistance", ty: TScalar}, {name: "support", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var lookback = IndicatorCache.intArg(args, 0, 4);
				var target = IndicatorCache.intArg(args, 1, 9);
				return IndicatorCache.evalBar(h, "td_lines:" + lookback + ":" + target,
					{resistance: Math.NaN, support: Math.NaN},
					() -> new TdLines(lookback, target), (i, b) -> (cast i : TdLines).update(b));
			}
		};
	}
}
