package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** Wave Trend output: the oscillator `wt1` and the signal SMA `wt2`. */
typedef WaveTrendOutput = {
	var wt1:Float;
	var wt2:Float;
}

/**
 * LazyBear's Wave Trend Oscillator — ported from wickra-core's `WaveTrend`
 * (vendor/wickra/crates/wickra-core/src/indicators/wave_trend.rs).
 *
 * For each candle let ap_t = (high + low + close) / 3:
 *
 *   esa_t = EMA(ap, channel_period)
 *   d_t   = EMA(|ap − esa|, channel_period)
 *   ci_t  = (ap_t − esa_t) / (0.015 * d_t)
 *   wt1_t = EMA(ci, average_period)
 *   wt2_t = SMA(wt1, signal_period)
 *
 * Classic defaults (channel = 10, average = 21, signal = 4). A sub-ULP
 * deviation `d` (flat market) collapses the channel index to zero. Warmup is
 * `2*channel + average + signal − 3` (SMA-seeded EMA cascade).
 */
class WaveTrend implements MuseIndicator<Bar, WaveTrendOutput> {
	/** f64::EPSILON — machine epsilon for the flat-market tolerance. */
	static inline var F64_EPSILON:Float = 2.220446049250313e-16;

	var channelPeriod:Int;
	var averagePeriod:Int;
	var signalPeriod:Int;
	var esa:Ema;
	var devEma:Ema;
	var tci:Ema;
	var signal:Sma;
	var last:Null<WaveTrendOutput>;

	public function new(channelPeriod:Int, averagePeriod:Int, signalPeriod:Int) {
		if (channelPeriod <= 0 || averagePeriod <= 0 || signalPeriod <= 0)
			throw "WaveTrend: period must be > 0";
		this.channelPeriod = channelPeriod;
		this.averagePeriod = averagePeriod;
		this.signalPeriod = signalPeriod;
		esa = new Ema(channelPeriod);
		devEma = new Ema(channelPeriod);
		tci = new Ema(averagePeriod);
		signal = new Sma(signalPeriod);
		last = null;
	}

	/** LazyBear's classic Wave Trend: (channel = 10, average = 21, signal = 4). */
	public static function classic():WaveTrend {
		return new WaveTrend(10, 21, 4);
	}

	public function update(candle:Bar):Null<WaveTrendOutput> {
		var ap = (candle.high + candle.low + candle.close) / 3.0;

		var esaV = esa.update(ap);
		if (esaV == null) return null;

		var d = devEma.update(Math.abs(ap - esaV));
		if (d == null) return null;

		// On a perfectly flat market (ap - esa) and d are both within an ULP
		// or two of zero; treat any sub-ULP deviation as zero (matches
		// pandas-ta's flat-market behaviour). Threshold scales with esa.
		var flatTol = Math.max(Math.abs(esaV), 1.0) * 16.0 * F64_EPSILON;
		var ci = d <= flatTol ? 0.0 : (ap - esaV) / (0.015 * d);

		var wt1 = tci.update(ci);
		if (wt1 == null) return null;

		var wt2 = signal.update(wt1);
		if (wt2 == null) return null;

		var out:WaveTrendOutput = { wt1: wt1, wt2: wt2 };
		last = out;
		return out;
	}

	public function reset():Void {
		esa.reset();
		devEma.reset();
		tci.reset();
		signal.reset();
		last = null;
	}

	public function warmupPeriod():Int return 2 * channelPeriod + averagePeriod + signalPeriod - 3;
	public function isReady():Bool return last != null;
	public function name():String return "WaveTrend";

	public static function spec():IndicatorSpec {
		return {
			name: "wave_trend", args: [TWindow, TWindow, TWindow], ret: TObject([
				{name: "wt1", ty: TScalar}, {name: "wt2", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var cp = args.length > 0 ? IndicatorCache.intArg(args, 0, 10) : 10;
				var ap = IndicatorCache.intArg(args, 1, 21);
				var sp = IndicatorCache.intArg(args, 2, 4);
				var nanFill = { wt1: Math.NaN, wt2: Math.NaN };
				return IndicatorCache.evalBar(h, "wave_trend:" + cp + ":" + ap + ":" + sp, nanFill,
					() -> new WaveTrend(cp, ap, sp), (i, b) -> (cast i : WaveTrend).update(b));
			}
		};
	}
}
