package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Elder Impulse System: colors each bar by whether both a trend EMA and a
 * MACD histogram are simultaneously rising, falling, or disagreeing.
 *
 * emaSlope = EMA(price, emaPeriod)_t - EMA(price, emaPeriod)_{t-1}
 * histSlope = MacdHist_t - MacdHist_{t-1}, MacdHist = EMA(price,fast) - EMA(price,slow) - Signal
 *
 * +1.0 (green/bullish): both slopes > 0.
 * -1.0 (red/bearish):   both slopes < 0.
 *  0.0 (blue/neutral):  slopes disagree (or either is exactly flat).
 */
class ElderImpulse implements MuseIndicator<Float, Float> {
	var trendEma:Ema;
	var fastEma:Ema;
	var slowEma:Ema;
	var signalEma:Ema;
	var lastTrend:Null<Float>;
	var lastHist:Null<Float>;

	public function new(emaPeriod:Int, fast:Int, slow:Int, signal:Int) {
		if (fast >= slow) throw "ElderImpulse: fast period must be strictly less than slow";
		trendEma = new Ema(emaPeriod);
		fastEma = new Ema(fast);
		slowEma = new Ema(slow);
		signalEma = new Ema(signal);
		lastTrend = null;
		lastHist = null;
	}

	public function update(price:Float):Null<Float> {
		var trend = trendEma.update(price);
		var f = fastEma.update(price);
		var s = slowEma.update(price);
		var hist:Null<Float> = null;
		if (f != null && s != null) {
			var macd = f - s;
			var sig = signalEma.update(macd);
			if (sig != null) hist = macd - sig;
		}

		if (trend == null || hist == null) {
			if (trend != null) lastTrend = trend;
			if (hist != null) lastHist = hist;
			return null;
		}

		var result:Null<Float> = null;
		if (lastTrend != null && lastHist != null) {
			var trendUp = trend > lastTrend;
			var trendDown = trend < lastTrend;
			var histUp = hist > lastHist;
			var histDown = hist < lastHist;
			if (trendUp && histUp) result = 1.0;
			else if (trendDown && histDown) result = -1.0;
			else result = 0.0;
		}
		lastTrend = trend;
		lastHist = hist;
		return result;
	}

	public function reset():Void {
		trendEma.reset();
		fastEma.reset();
		slowEma.reset();
		signalEma.reset();
		lastTrend = null;
		lastHist = null;
	}

	public function warmupPeriod():Int {
		var m = slowEma.period + signalEma.period;
		if (trendEma.period > m) m = trendEma.period;
		return m + 1;
	}
	public function isReady():Bool return lastTrend != null && lastHist != null;
	public function name():String return "ElderImpulse";

	public static function spec():IndicatorSpec {
		return {
			name: "elder_impulse", args: [TSeries, TWindow, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var emaPeriod = IndicatorCache.intArg(args, 1, 13);
				var fast = IndicatorCache.intArg(args, 2, 12);
				var slow = IndicatorCache.intArg(args, 3, 26);
				var signal = IndicatorCache.intArg(args, 4, 9);
				var key = "elder_impulse:" + series + ":" + emaPeriod + ":" + fast + ":" + slow + ":" + signal;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new ElderImpulse(emaPeriod, fast, slow, signal), (i, v) -> (cast i : ElderImpulse).update(v));
			}
		};
	}
}
