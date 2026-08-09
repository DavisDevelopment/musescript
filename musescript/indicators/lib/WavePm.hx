package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Wave PM — Cynthia Kase's peak-momentum statistic; ported from wickra-core's
 * `WavePm` (vendor/wickra/crates/wickra-core/src/indicators/wave_pm.rs),
 * itself a Wickra reconstruction of the platform-specific published form.
 *
 * A `0..100` statistic that rises when the current `length`-bar momentum is
 * large relative to its own recent energy:
 *
 * m      = close_t − close_{t−length}
 * energy = EMA(m², length)
 * raw    = 1 − exp( −m² / (2·energy) )    (0 if energy == 0)
 * WavePM = 100 · EMA(raw, smoothing)
 *
 * A steady trend pins at the baseline `100·(1 − e^{−1/2}) ≈ 39.35`; a
 * momentum spike drives the reading toward 100; a flat market reads 0.
 * Warmup is `2·length + smoothing − 1`.
 *
 * Reference: Cynthia Kase, *Trading with the Odds*, 1996.
 */
class WavePm implements MuseIndicator<Float, Float> {
	var length:Int;
	var smoothing:Int;
	var closes:RingBuffer<Float>;
	var energyEma:Ema;
	var smoothEma:Ema;

	public function new(length:Int, smoothing:Int) {
		if (length == 0) throw "WavePm: period must be > 0";
		this.length = length;
		this.smoothing = smoothing;
		closes = new RingBuffer(length + 1);
		energyEma = new Ema(length);
		smoothEma = new Ema(smoothing); // throws for smoothing == 0, matching Rust's Ema::new
	}

	public function update(close:Float):Null<Float> {
		closes.push(close);
		if (closes.length <= length) return null;

		var oldest = closes.oldest(0);
		var momentum = close - oldest;
		var energy = energyEma.update(momentum * momentum);
		if (energy == null) return null;
		var raw = energy <= 0.0 ? 0.0 : 1.0 - Math.exp(-(momentum * momentum) / (2.0 * energy));
		var s = smoothEma.update(raw);
		return s == null ? null : s * 100.0;
	}

	public function reset():Void {
		closes = new RingBuffer(length + 1);
		energyEma.reset();
		smoothEma.reset();
	}

	public function warmupPeriod():Int return 2 * length + smoothing - 1;
	public function isReady():Bool return smoothEma.isReady();
	public function name():String return "WavePm";

	public static function spec():IndicatorSpec {
		return {
			name: "wave_pm", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var len = IndicatorCache.intArg(args, 1, 10);
				var smooth = IndicatorCache.intArg(args, 2, 3);
				var key = "wave_pm:" + series + ":" + len + ":" + smooth;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new WavePm(len, smooth), (i, v) -> (cast i : WavePm).update(v));
			}
		};
	}
}
