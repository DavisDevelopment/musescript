package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Twiggs Money Flow — ported from wickra-core's `TwiggsMoneyFlow`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/twiggs_money_flow.rs).
 *
 *   TRH = max(high, prev_close)          (true high)
 *   TRL = min(low,  prev_close)          (true low)
 *   ad  = volume * (2*close - TRH - TRL) / (TRH - TRL)   (0 if TRH == TRL)
 *   TMF = WilderEMA(ad, period) / WilderEMA(volume, period)
 *
 * Roughly bounded in [-1, +1]. The first candle seeds the reference close;
 * the next `period` bars seed both Wilder averages, so the first value lands
 * after `period + 1` inputs. A zero smoothed volume reports 0 rather than 0/0.
 */
class TwiggsMoneyFlow implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var prevClose:Null<Float>;
	var seedAd:Float;
	var seedVol:Float;
	var seedCount:Int;
	var adEma:Null<Float>;
	var volEma:Null<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "TwiggsMoneyFlow: period must be > 0";
		this.period = period;
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return last;

	static function ratio(adEma:Float, volEma:Float):Float {
		return volEma == 0.0 ? 0.0 : adEma / volEma;
	}

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = bar.close;
			return null;
		}
		var prev:Float = prevClose;
		var trh = Math.max(bar.high, prev);
		var trl = Math.min(bar.low, prev);
		var range = trh - trl;
		var ad = range > 0.0 ? bar.volume * (2.0 * bar.close - trh - trl) / range : 0.0;
		prevClose = bar.close;

		if (adEma != null && volEma != null) {
			var n:Float = period;
			var newAd = adEma + (ad - adEma) / n;
			var newVol = volEma + (bar.volume - volEma) / n;
			adEma = newAd;
			volEma = newVol;
			var v = ratio(newAd, newVol);
			last = v;
			return v;
		}

		seedAd += ad;
		seedVol += bar.volume;
		seedCount += 1;
		if (seedCount == period) {
			var n:Float = period;
			var a = seedAd / n;
			var vo = seedVol / n;
			adEma = a;
			volEma = vo;
			var v = ratio(a, vo);
			last = v;
			return v;
		}
		return null;
	}

	public function reset():Void {
		prevClose = null;
		seedAd = 0.0;
		seedVol = 0.0;
		seedCount = 0;
		adEma = null;
		volEma = null;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "TwiggsMoneyFlow";

	public static function spec():IndicatorSpec {
		return {
			name: "twiggs_money_flow", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 21);
				return IndicatorCache.evalBar(h, "twiggs_money_flow:" + p, Math.NaN,
					() -> new TwiggsMoneyFlow(p), (i, b) -> (cast i : TwiggsMoneyFlow).update(b));
			}
		};
	}
}
