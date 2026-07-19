package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Polarized Fractal Efficiency (PFE) — price movement efficiency over period bars.
 * Ported from wickra-core's `PolarizedFractalEfficiency`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/polarized_fractal_efficiency.rs).
 *
 * Polarized Fractal Efficiency: how efficiently price travelled over the last
 * `period` bars, signed by direction and smoothed by an EMA.
 *
 * straight  = sqrt((C_t - C_{t-n})^2 + n^2)            (direct distance over n bars)
 * path      = Σ_{i=1..n} sqrt((C_{t-i+1} - C_{t-i})^2 + 1)   (sum of single-bar steps)
 * raw       = 100 * sign(C_t - C_{t-n}) * straight / path
 * PFE       = EMA(raw, smoothing)
 *
 * The ratio `straight / path` is the fractal efficiency: it is `1` when price
 * moved in a perfectly straight line and falls toward `0` as the path becomes
 * jagged. Polarizing it by the sign of the net move pushes the reading to
 * `+100` for an efficient up-move and `-100` for an efficient down-move, with
 * choppy markets oscillating near zero.
 *
 * Reference: Hans Hannula, Stocks & Commodities, 1994.
 */
class PolarizedFractalEfficiency implements MuseIndicator<Float, Float> {
	var period:Int;
	var smoothing:Int;
	var closes:Array<Float>;
	var prev_close:Null<Float>;
	var segments:Array<Float>;
	var segment_sum:Float;
	var ema:Ema;

	public function new(period:Int, smoothing:Int) {
		if (period <= 0 || smoothing <= 0) throw "PolarizedFractalEfficiency: periods must be > 0";
		this.period = period;
		this.smoothing = smoothing;
		closes = [];
		prev_close = null;
		segments = [];
		segment_sum = 0.0;
		ema = new Ema(smoothing);
	}

	public function update(close:Float):Null<Float> {
		if (!Math.isFinite(close)) return null;

		if (prev_close != null) {
			var prev = prev_close;
			var diff = close - prev;
			var segment = Math.sqrt(diff * diff + 1.0);
			segment_sum += segment;
			segments.push(segment);
			if (segments.length > period) {
				var removed = segments.shift();
				segment_sum -= removed;
			}
		}
		prev_close = close;

		closes.push(close);
		if (closes.length > period + 1) {
			closes.shift();
		}
		if (closes.length <= period) {
			return null;
		}

		var oldest = closes[0];
		var net = close - oldest;
		var direction = if (net > 0.0) {
			1.0;
		} else if (net < 0.0) {
			-1.0;
		} else {
			0.0;
		};
		var span = period;
		var straight = Math.sqrt(net * net + span * span);
		var raw = 100.0 * direction * straight / segment_sum;
		return ema.update(raw);
	}

	public function reset():Void {
		closes = [];
		prev_close = null;
		segments = [];
		segment_sum = 0.0;
		ema.reset();
	}

	public function warmupPeriod():Int return period + smoothing;
	public function isReady():Bool return ema.isReady();
	public function name():String return "PolarizedFractalEfficiency";

	public static function spec():IndicatorSpec {
		return {
			name: "pfe", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 10);
				var s = IndicatorCache.intArg(args, 2, 5);
				return IndicatorCache.evalSeries(h, "pfe:" + series + ":" + p + ":" + s, series, Math.NaN,
					() -> new PolarizedFractalEfficiency(p, s), (i, v) -> (cast i : PolarizedFractalEfficiency).update(v));
			}
		};
	}
}
