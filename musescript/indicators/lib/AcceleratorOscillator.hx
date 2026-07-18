package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Accelerator Oscillator (Bill Williams) — ported from wickra-core's `AcceleratorOscillator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/accelerator_oscillator.rs).
 *
 * Bill Williams' gauge of momentum's acceleration: the Awesome Oscillator minus
 * a short moving average of itself. Because acceleration leads speed, AC tends to
 * turn before the AO does.
 *
 * AO = SMA(median, fast) − SMA(median, slow)   (the Awesome Oscillator)
 * AC = AO − SMA(AO, signal)
 *
 * Classic configuration is AO(5, 34) with a 5-period signal average.
 */
class AcceleratorOscillator implements MuseIndicator<Bar, Float> {
	var ao:AwesomeOscillator;
	var signal:Sma;
	var aoFast:Int;
	var aoSlow:Int;
	var signalPeriod:Int;

	public function new(aoFast:Int, aoSlow:Int, signalPeriod:Int) {
		this.ao = new AwesomeOscillator(aoFast, aoSlow);
		this.signal = new Sma(signalPeriod);
		this.aoFast = aoFast;
		this.aoSlow = aoSlow;
		this.signalPeriod = signalPeriod;
	}

	public function update(bar:Bar):Null<Float> {
		var aoVal = ao.update(bar);
		if (aoVal == null) return null;
		var signalVal = signal.update(aoVal);
		if (signalVal == null) return null;
		return aoVal - signalVal;
	}

	public function reset():Void {
		ao.reset();
		signal.reset();
	}

	public function warmupPeriod():Int return ao.warmupPeriod() + signalPeriod - 1;
	public function isReady():Bool return signal.isReady();
	public function name():String return "AcceleratorOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "accelerator_oscillator", args: [TWindow, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var f = IndicatorCache.intArg(args, 0, 5);
				var s = IndicatorCache.intArg(args, 1, 34);
				var sig = IndicatorCache.intArg(args, 2, 5);
				return IndicatorCache.evalBar(h, "accelerator_oscillator:" + f + ":" + s + ":" + sig, Math.NaN,
					() -> new AcceleratorOscillator(f, s, sig), (i, b) -> (cast i : AcceleratorOscillator).update(b));
			}
		};
	}
}
