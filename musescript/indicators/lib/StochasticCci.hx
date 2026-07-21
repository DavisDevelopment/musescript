package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.Cci;
import musescript.types.MuseType;

/**
 * Stochastic CCI — ported from wickra-core's `StochasticCci`
 * (vendor/wickra/crates/wickra-core/src/indicators/stochastic_cci.rs).
 *
 * The stochastic oscillator computed over the CCI instead of price:
 *
 *   cci = CCI(typical price, period)
 *   %K  = 100 · (cci − lowest(cci, period)) / (highest(cci, period) − lowest(cci, period))
 *
 * The same `period` is used for the CCI and the stochastic lookback. A zero
 * CCI range over the window returns the neutral 50. The first value lands
 * after 2·period − 1 bars.
 */
class StochasticCci implements MuseIndicator<Bar, Float> {
	var period:Int;
	var cci:Cci;
	/** The last `period` CCI values. */
	var window:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "StochasticCci: period must be > 0";
		this.period = period;
		cci = new Cci(period);
		window = [];
	}

	public function update(bar:Bar):Null<Float> {
		var c = cci.update(bar);
		if (c == null) return null;
		if (window.length == period) window.shift();
		window.push(c);
		if (window.length < period) return null;
		var lo = window[0];
		var hi = window[0];
		for (v in window) {
			if (v < lo) lo = v;
			if (v > hi) hi = v;
		}
		var range = hi - lo;
		if (range == 0.0) return 50.0;
		// Ratio first, then scale: `100 * x / x` can round to 100.0000…1.
		return 100.0 * ((c - lo) / range);
	}

	public function reset():Void {
		cci.reset();
		window = [];
	}

	public function warmupPeriod():Int {
		// CCI seeds at `period`, then `period` CCI values fill the stochastic window.
		return 2 * period - 1;
	}

	public function isReady():Bool return window.length == period;
	public function name():String return "StochasticCCI";

	public static function spec():IndicatorSpec {
		return {
			name: "stochastic_cci", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var key = "stochastic_cci:" + p;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new StochasticCci(p), (i, b) -> (cast i : StochasticCci).update(b));
			}
		};
	}
}
