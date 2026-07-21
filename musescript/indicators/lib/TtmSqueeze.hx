package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.Bollinger;
import musescript.indicators.prim.Atr;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** TTM Squeeze output: squeeze flag (1/0) and detrended momentum. */
typedef TtmSqueezeOutput = {
	var squeeze:Float;
	var momentum:Float;
}

/**
 * TTM Squeeze (John Carter) — ported from wickra-core's `TtmSqueeze`
 * (vendor/wickra/crates/wickra-core/src/indicators/ttm_squeeze.rs).
 *
 *   squeeze  = 1.0 if BollingerBands(period, bb_mult)
 *                  ⊂ Keltner-like(SMA(period), ATR(period), kc_mult)
 *              else 0.0
 *   hl_mid   = (max(high, period) + min(low, period)) / 2
 *   detrend  = close − (hl_mid + SMA(close, period)) / 2
 *   momentum = LinearRegression(detrend, period)        // endpoint
 *
 * The Keltner-like envelope uses an SMA centerline plus an ATR offset,
 * exactly as Carter's original publication defines it. Classic parameters:
 * period = 20, bb_mult = 2.0, kc_mult = 1.5. First value after `period` bars.
 */
class TtmSqueeze implements MuseIndicator<Bar, TtmSqueezeOutput> {
	var period:Int;
	var bbMult:Float;
	var kcMult:Float;
	var bb:Bollinger;
	var smaClose:Sma;
	var atr:Atr;
	var highs:Array<Float>;
	var lows:Array<Float>;
	var closes:Array<Float>;
	// Pre-computed OLS constants over x = 0..period − 1.
	var sumX:Float;
	var denom:Float;

	public function new(period:Int, bbMult:Float, kcMult:Float) {
		if (period < 2) throw "TtmSqueeze: TTM squeeze needs period >= 2 for the momentum regression";
		if (!Math.isFinite(bbMult) || bbMult <= 0.0 || !Math.isFinite(kcMult) || kcMult <= 0.0)
			throw "TtmSqueeze: multiplier must be positive and finite";
		this.period = period;
		this.bbMult = bbMult;
		this.kcMult = kcMult;
		var n:Float = period;
		sumX = n * (n - 1.0) / 2.0;
		var sumXx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;
		denom = n * sumXx - sumX * sumX;
		bb = new Bollinger(period, bbMult);
		smaClose = new Sma(period);
		atr = new Atr(period);
		highs = [];
		lows = [];
		closes = [];
	}

	/** John Carter's classic configuration: period = 20, bb_mult = 2.0, kc_mult = 1.5. */
	public static function classic():TtmSqueeze {
		return new TtmSqueeze(20, 2.0, 1.5);
	}

	public function update(candle:Bar):Null<TtmSqueezeOutput> {
		if (highs.length == period) {
			highs.shift();
			lows.shift();
			closes.shift();
		}
		highs.push(candle.high);
		lows.push(candle.low);
		closes.push(candle.close);

		// Feed all three sub-indicators unconditionally so they warm up in
		// lock-step (all first emit at bar `period`).
		var bbOut = bb.update(candle.close);
		var mid = smaClose.update(candle.close);
		var atrV = atr.update(candle);
		if (bbOut == null || mid == null || atrV == null) return null;

		var kcUpper = mid + kcMult * atrV;
		var kcLower = mid - kcMult * atrV;
		var squeeze = (bbOut.upper <= kcUpper && bbOut.lower >= kcLower) ? 1.0 : 0.0;

		// Detrended close: deviation of close from the average of the rolling
		// high-low midpoint and the SMA of close, then a linear regression of
		// that series (endpoint value).
		var hi = Math.NEGATIVE_INFINITY;
		for (h in highs) if (h > hi) hi = h;
		var lo = Math.POSITIVE_INFINITY;
		for (l in lows) if (l < lo) lo = l;
		var hlMid = (hi + lo) / 2.0;
		var baseline = (hlMid + mid) / 2.0;
		var sumY = 0.0;
		var sumXy = 0.0;
		for (i in 0...closes.length) {
			var y = closes[i] - baseline;
			sumY += y;
			sumXy += i * y;
		}
		var n:Float = period;
		var slope = (n * sumXy - sumX * sumY) / denom;
		var intercept = (sumY - slope * sumX) / n;
		var momentum = intercept + slope * (n - 1.0);

		return { squeeze: squeeze, momentum: momentum };
	}

	public function reset():Void {
		bb.reset();
		smaClose.reset();
		atr.reset();
		highs = [];
		lows = [];
		closes = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return bb.isReady() && smaClose.isReady() && atr.isReady();
	public function name():String return "TtmSqueeze";

	public static function spec():IndicatorSpec {
		return {
			name: "ttm_squeeze", args: [TWindow, TScalar, TScalar], ret: TObject([
				{name: "squeeze", ty: TScalar}, {name: "momentum", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = args.length > 0 ? IndicatorCache.intArg(args, 0, 20) : 20;
				var bm = IndicatorCache.floatArg(args, 1, 2.0);
				var km = IndicatorCache.floatArg(args, 2, 1.5);
				var nanFill = { squeeze: Math.NaN, momentum: Math.NaN };
				return IndicatorCache.evalBar(h, "ttm_squeeze:" + p + ":" + bm + ":" + km, nanFill,
					() -> new TtmSqueeze(p, bm, km), (i, b) -> (cast i : TtmSqueeze).update(b));
			}
		};
	}
}
