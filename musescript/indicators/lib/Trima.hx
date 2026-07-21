package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Triangular Moving Average — ported from wickra-core's `Trima`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/trima.rs).
 *
 * A simple moving average applied twice, which triangular-weights the window
 * so the middle bars carry the most weight. For period `n` the two stacked
 * SMAs use lengths `n1`/`n2`: odd `n` uses `n1 = n2 = (n+1)/2`; even `n` uses
 * `n1 = n/2`, `n2 = n/2 + 1`. First output after exactly `n` inputs.
 * Series input (f64): `trima(close, period)`.
 */
class Trima implements MuseIndicator<Float, Float> {
	var period:Int;
	var inner:Sma;
	var outer:Sma;

	public function new(period:Int) {
		if (period <= 0) throw "Trima: period must be > 0";
		this.period = period;
		var n1:Int;
		var n2:Int;
		if (period % 2 == 1) {
			n1 = Std.int((period + 1) / 2);
			n2 = n1;
		} else {
			n1 = Std.int(period / 2);
			n2 = Std.int(period / 2) + 1;
		}
		inner = new Sma(n1);
		outer = new Sma(n2);
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	/** Current value if available. */
	public function value():Null<Float> {
		return outer.isReady() ? outer.value() : null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; do not double-feed the inner SMA's
			// stale value into the outer SMA.
			return value();
		}
		// Genuine stacking: the outer SMA consumes the inner SMA's output.
		var v = inner.update(input);
		if (v == null) return null;
		return outer.update(v);
	}

	public function reset():Void {
		inner.reset();
		outer.reset();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return outer.isReady();
	public function name():String return "TRIMA";

	public static function spec():IndicatorSpec {
		return {
			name: "trima", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "trima:" + series + ":" + p, series, Math.NaN,
					() -> new Trima(p), (i, v) -> (cast i : Trima).update(v));
			}
		};
	}
}
