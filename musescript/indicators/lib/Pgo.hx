package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Pretty Good Oscillator (Mark Johnson) — ported from wickra-core's `Pgo`
 * (vendor/wickra/crates/wickra-core/src/indicators/pgo.rs).
 *
 *   PGO_t = (close_t − SMA(close, period)_t) / EMA(TR_t, period)
 *
 * Roughly "how many ATR-equivalents is the close away from its mean?".
 * The true range always emits (falls back to high − low without a previous
 * close). On a zero-volatility window (EMA(TR) <= 0) the previous value is
 * held rather than dividing by zero. First value after `period` candles.
 */
class Pgo implements MuseIndicator<Bar, Float> {
	var period:Int;
	var sma:Sma;
	var emaTr:Ema;
	var hasPrevClose:Bool;
	var prevClose:Float;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Pgo: period must be > 0";
		this.period = period;
		sma = new Sma(period);
		emaTr = new Ema(period);
		hasPrevClose = false;
		prevClose = 0.0;
		current = null;
	}

	public function update(candle:Bar):Null<Float> {
		var mean = sma.update(candle.close);
		// TrueRange always emits (no previous close -> high − low).
		var tr = candle.high - candle.low;
		if (hasPrevClose) {
			var hc = Math.abs(candle.high - prevClose);
			var lc = Math.abs(candle.low - prevClose);
			tr = Math.max(tr, Math.max(hc, lc));
		}
		prevClose = candle.close;
		hasPrevClose = true;
		var emaV = emaTr.update(tr);
		if (mean == null) return null;
		if (emaV == null) return null;
		if (emaV <= 0.0) {
			// Pathological window of perfectly flat candles: divisor zero.
			// Hold the previous value rather than blow up.
			return current;
		}
		var value = (candle.close - mean) / emaV;
		current = value;
		return value;
	}

	public function reset():Void {
		sma.reset();
		emaTr.reset();
		hasPrevClose = false;
		prevClose = 0.0;
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "PGO";

	public static function spec():IndicatorSpec {
		return {
			name: "pgo", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "pgo:" + p, Math.NaN,
					() -> new Pgo(p), (i, b) -> (cast i : Pgo).update(b));
			}
		};
	}
}
