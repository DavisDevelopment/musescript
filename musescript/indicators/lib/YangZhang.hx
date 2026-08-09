package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Yang-Zhang Volatility — ported from wickra-core's `YangZhangVolatility`
 * (vendor/wickra/crates/wickra-core/src/indicators/yang_zhang.rs).
 *
 * Combines overnight, open-to-close, and Rogers-Satchell volatilities into
 * a single drift- and gap-robust estimator (Yang & Zhang 2000):
 *
 *   k     = 0.34 / (1.34 + (n + 1) / (n − 1))
 *   σ²_on = sample_var(ln(O_t / C_{t-1}) over n bars)
 *   σ²_oc = sample_var(ln(C_t / O_t) over n bars)
 *   σ²_rs = mean(ln(H/C)·ln(H/O) + ln(L/C)·ln(L/O) over n bars)
 *   σ²_YZ = σ²_on + k·σ²_oc + (1 − k)·σ²_rs
 *   out   = √max(σ²_YZ, 0) · √trading_periods · 100
 *
 * Sample variances use Bessel's correction (divisor n − 1). First value
 * after `period + 1` bars (one bar seeds the previous close).
 */
class YangZhang implements MuseIndicator<Bar, Float> {
	var period:Int;
	var tradingPeriods:Int;
	var k:Float;
	var prevClose:Null<Float>;
	var overnight:RingBuffer<Float>;
	var openClose:RingBuffer<Float>;
	var rsSamples:RingBuffer<Float>;
	var sumOn:Float;
	var sumSqOn:Float;
	var sumOc:Float;
	var sumSqOc:Float;
	var sumRs:Float;
	var last:Null<Float>;

	public function new(period:Int, tradingPeriods:Int) {
		if (period <= 0 || tradingPeriods <= 0) throw "YangZhang: period must be > 0";
		if (period < 2) throw "YangZhang: Yang-Zhang period must be >= 2";
		this.period = period;
		this.tradingPeriods = tradingPeriods;
		var n:Float = period;
		k = 0.34 / (1.34 + (n + 1.0) / (n - 1.0));
		reset();
	}

	/** The Yang-Zhang blending factor `k` for this configuration. */
	public function blendingFactor():Float return k;

	public function update(candle:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = candle.close;
			return null;
		}
		var prevC:Float = prevClose;
		prevClose = candle.close;

		var onSample = Math.log(candle.open / prevC);
		var ocSample = Math.log(candle.close / candle.open);
		var logHc = Math.log(candle.high / candle.close);
		var logHo = Math.log(candle.high / candle.open);
		var logLc = Math.log(candle.low / candle.close);
		var logLo = Math.log(candle.low / candle.open);
		var rsSample = logHc * logHo + logLc * logLo;

		// Roll the three windows — evict/subtract before add (ULP order).
		var wasFull = overnight.isFull();
		var oldOn = overnight.push(onSample);
		var oldOc = openClose.push(ocSample);
		var oldRs = rsSamples.push(rsSample);
		if (wasFull) {
			sumOn -= oldOn;
			sumSqOn -= oldOn * oldOn;
			sumOc -= oldOc;
			sumSqOc -= oldOc * oldOc;
			sumRs -= oldRs;
		}
		sumOn += onSample;
		sumSqOn += onSample * onSample;
		sumOc += ocSample;
		sumSqOc += ocSample * ocSample;
		sumRs += rsSample;

		if (overnight.length < period) return null;

		var n:Float = period;
		var meanOn = sumOn / n;
		var meanOc = sumOc / n;
		// Sample variances (Bessel's correction), clamped against FP noise.
		var varOn = Math.max((sumSqOn - n * meanOn * meanOn) / (n - 1.0), 0.0);
		var varOc = Math.max((sumSqOc - n * meanOc * meanOc) / (n - 1.0), 0.0);
		var varRs = Math.max(sumRs / n, 0.0);

		var total = varOn + k * varOc + (1.0 - k) * varRs;
		var sigma = Math.sqrt(Math.max(total, 0.0));
		var out = sigma * Math.sqrt(tradingPeriods) * 100.0;
		last = out;
		return out;
	}

	public function reset():Void {
		prevClose = null;
		overnight = new RingBuffer(period);
		openClose = new RingBuffer(period);
		rsSamples = new RingBuffer(period);
		sumOn = 0.0;
		sumSqOn = 0.0;
		sumOc = 0.0;
		sumSqOc = 0.0;
		sumRs = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "YangZhangVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "yang_zhang", args: [TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var tp = IndicatorCache.intArg(args, 1, 252);
				return IndicatorCache.evalBar(h, "yang_zhang:" + p + ":" + tp, Math.NaN,
					() -> new YangZhang(p, tp), (i, b) -> (cast i : YangZhang).update(b));
			}
		};
	}
}
