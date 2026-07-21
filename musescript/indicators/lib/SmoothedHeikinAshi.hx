package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/** One smoothed Heikin-Ashi candle. */
typedef SmoothedHeikinAshiOutput = {
	var open:Float;
	var high:Float;
	var low:Float;
	var close:Float;
}

/**
 * Smoothed Heikin-Ashi — ported from wickra-core's `SmoothedHeikinAshi`
 * (vendor/wickra/crates/wickra-core/src/indicators/smoothed_heikin_ashi.rs).
 *
 * The Heikin-Ashi transform applied to EMA-smoothed OHLC, for an even
 * cleaner trend view:
 *
 *   eo, eh, el, ec = EMA(open|high|low|close, period)
 *   ha_close = (eo + eh + el + ec) / 4
 *   ha_open  = (prev_ha_open + prev_ha_close) / 2     (seeded with (eo + ec)/2)
 *   ha_high  = max(eh, ha_open, ha_close)
 *   ha_low   = min(el, ha_open, ha_close)
 *
 * The first value lands once the EMAs are seeded (`period` inputs).
 */
class SmoothedHeikinAshi implements MuseIndicator<Bar, SmoothedHeikinAshiOutput> {
	var period:Int;
	var emaOpen:Ema;
	var emaHigh:Ema;
	var emaLow:Ema;
	var emaClose:Ema;
	var prev:Null<SmoothedHeikinAshiOutput>;
	var last:Null<SmoothedHeikinAshiOutput>;

	public function new(period:Int) {
		if (period <= 0) throw "SmoothedHeikinAshi: period must be > 0";
		this.period = period;
		emaOpen = new Ema(period);
		emaHigh = new Ema(period);
		emaLow = new Ema(period);
		emaClose = new Ema(period);
		prev = null;
		last = null;
	}

	/** Current value if available. */
	public function value():Null<SmoothedHeikinAshiOutput> return last;

	public function update(candle:Bar):Null<SmoothedHeikinAshiOutput> {
		var eo = emaOpen.update(candle.open);
		var eh = emaHigh.update(candle.high);
		var el = emaLow.update(candle.low);
		var ec = emaClose.update(candle.close);
		if (eo == null || eh == null || el == null || ec == null) return null;
		var vo:Float = eo;
		var vh:Float = eh;
		var vl:Float = el;
		var vc:Float = ec;
		var haClose = (vo + vh + vl + vc) / 4.0;
		var haOpen = prev != null ? (prev.open + prev.close) / 2.0 : (vo + vc) / 2.0;
		var haHigh = Math.max(vh, Math.max(haOpen, haClose));
		var haLow = Math.min(vl, Math.min(haOpen, haClose));
		var out:SmoothedHeikinAshiOutput = {
			open: haOpen,
			high: haHigh,
			low: haLow,
			close: haClose
		};
		prev = out;
		last = out;
		return out;
	}

	public function reset():Void {
		emaOpen.reset();
		emaHigh.reset();
		emaLow.reset();
		emaClose.reset();
		prev = null;
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "SmoothedHeikinAshi";

	public static function spec():IndicatorSpec {
		return {
			name: "smoothed_heikin_ashi", args: [TWindow], ret: TObject([
				{name: "open", ty: TScalar}, {name: "high", ty: TScalar}, {name: "low", ty: TScalar}, {name: "close", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				var nanFill = { open: Math.NaN, high: Math.NaN, low: Math.NaN, close: Math.NaN };
				return IndicatorCache.evalBar(h, "smoothed_heikin_ashi:" + p, nanFill,
					() -> new SmoothedHeikinAshi(p), (i, b) -> (cast i : SmoothedHeikinAshi).update(b));
			}
		};
	}
}
