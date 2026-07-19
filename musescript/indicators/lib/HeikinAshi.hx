package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Heikin-Ashi output: the synthetic smoothed OHLC candle. */
typedef HeikinAshiOutput = {
	var open:Float;
	var high:Float;
	var low:Float;
	var close:Float;
}

/**
 * Heikin-Ashi: a smoothed synthetic candle series that filters out noise by
 * averaging each bar with the running synthetic state, making trends easier
 * to read at a glance.
 *
 * haClose = (open + high + low + close) / 4
 * haOpen  = (prevHaOpen + prevHaClose) / 2     (first bar: (open + close) / 2)
 * haHigh  = max(high, haOpen, haClose)
 * haLow   = min(low, haOpen, haClose)
 */
class HeikinAshi implements MuseIndicator<Bar, HeikinAshiOutput> {
	var prevHaOpen:Null<Float>;
	var prevHaClose:Null<Float>;

	public function new() {
		prevHaOpen = null;
		prevHaClose = null;
	}

	public function update(bar:Bar):Null<HeikinAshiOutput> {
		var haClose = (bar.open + bar.high + bar.low + bar.close) / 4.0;
		var haOpen = if (prevHaOpen == null || prevHaClose == null) {
			(bar.open + bar.close) / 2.0;
		} else {
			(prevHaOpen + prevHaClose) / 2.0;
		}
		var haHigh = Math.max(bar.high, Math.max(haOpen, haClose));
		var haLow = Math.min(bar.low, Math.min(haOpen, haClose));

		prevHaOpen = haOpen;
		prevHaClose = haClose;

		return { open: haOpen, high: haHigh, low: haLow, close: haClose };
	}

	public function reset():Void {
		prevHaOpen = null;
		prevHaClose = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return prevHaOpen != null;
	public function name():String return "HeikinAshi";

	public static function spec():IndicatorSpec {
		return {
			name: "heikin_ashi", args: [], ret: TObject([
				{name: "open", ty: TScalar}, {name: "high", ty: TScalar}, {name: "low", ty: TScalar}, {name: "close", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { open: Math.NaN, high: Math.NaN, low: Math.NaN, close: Math.NaN };
				return IndicatorCache.evalBar(h, "heikin_ashi", nanFill,
					() -> new HeikinAshi(), (i, b) -> (cast i : HeikinAshi).update(b));
			}
		};
	}
}
