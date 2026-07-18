package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Awesome Oscillator (Bill Williams) — ported from wickra-core's `AwesomeOscillator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/awesome_oscillator.rs).
 *
 * `AO = SMA(median_price, fast) − SMA(median_price, slow)`.
 * Classic Bill Williams configuration is (5, 34).
 */
class AwesomeOscillator implements MuseIndicator<Bar, Float> {
	var fast:Sma;
	var slow:Sma;
	var fastPeriod:Int;
	var slowPeriod:Int;

	public function new(fast:Int, slow:Int) {
		if (fast <= 0 || slow <= 0) throw "AwesomeOscillator: periods must be > 0";
		// Ensure fast < slow; swap if needed to be lenient with parameter order
		var f = Math.min(fast, slow);
		var s = Math.max(fast, slow);
		// If periods are equal, adjust to defaults for leniency
		if (f == s) {
			f = 5;
			s = 34;
		}
		this.fast = new Sma(cast f);
		this.slow = new Sma(cast s);
		this.fastPeriod = cast f;
		this.slowPeriod = cast s;
	}


	public function update(bar:Bar):Null<Float> {
		var median = (bar.high + bar.low) / 2.0;
		var f = fast.update(median);
		var s = slow.update(median);
		if (f == null || s == null) return null;
		return f - s;
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
	}

	public function warmupPeriod():Int return slowPeriod;
	public function isReady():Bool return slow.isReady();
	public function name():String return "AwesomeOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "awesome_oscillator", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var f = IndicatorCache.intArg(args, 0, 5);
				var s = IndicatorCache.intArg(args, 1, 34);
				return IndicatorCache.evalBar(h, "awesome_oscillator:" + f + ":" + s, Math.NaN,
					() -> new AwesomeOscillator(f, s), (i, b) -> (cast i : AwesomeOscillator).update(b));
			}
		};
	}
}
