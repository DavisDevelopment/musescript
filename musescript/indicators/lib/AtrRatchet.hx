package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** ATR Ratchet output: stop level and direction. */
typedef AtrRatchetOutput = {
	var value:Float;
	var direction:Float;
}

/**
 * ATR Ratchet — ported from wickra-core's `AtrRatchet`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/atr_ratchet.rs).
 *
 * Perry Kaufman's time-based volatility stop that tightens by a fixed fraction
 * of ATR every bar, whether or not price moves. The initial distance
 * (`start_mult · ATR`) gives room to breathe; the per-bar `increment` controls
 * how aggressively the leash shortens.
 *
 * on entry (long):   stop = close − start_mult · ATR
 * each later bar:     stop = stop + increment · ATR    (ratchets toward price)
 * flip to short when  close < stop, reseeding stop = close + start_mult · ATR
 */
class AtrRatchet implements MuseIndicator<Bar, AtrRatchetOutput> {
	var atr:Atr;
	var atrPeriod:Int;
	var startMult:Float;
	var increment:Float;
	var direction:Float;
	var stop:Float;
	var last:Null<AtrRatchetOutput>;

	public function new(atrPeriod:Int, startMult:Float, increment:Float) {
		if (!Math.isFinite(startMult) || startMult <= 0.0) throw "AtrRatchet: startMult must be positive and finite";
		if (!Math.isFinite(increment) || increment <= 0.0) throw "AtrRatchet: increment must be positive and finite";
		this.atr = new Atr(atrPeriod);
		this.atrPeriod = atrPeriod;
		this.startMult = startMult;
		this.increment = increment;
		direction = 0.0;
		stop = 0.0;
		last = null;
	}

	public function update(bar:Bar):Null<AtrRatchetOutput> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;

		var close = bar.close;

		if (direction == 0.0) {
			direction = 1.0;
			stop = close - startMult * atrVal;
		} else if (direction > 0.0) {
			stop += increment * atrVal;
			if (close < stop) {
				direction = -1.0;
				stop = close + startMult * atrVal;
			}
		} else {
			stop -= increment * atrVal;
			if (close > stop) {
				direction = 1.0;
				stop = close - startMult * atrVal;
			}
		}

		var out:AtrRatchetOutput = {
			value: stop,
			direction: direction
		};
		last = out;
		return out;
	}

	public function reset():Void {
		atr.reset();
		direction = 0.0;
		stop = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return atrPeriod;
	public function isReady():Bool return last != null;
	public function name():String return "AtrRatchet";

	public static function spec():IndicatorSpec {
		return {
			name: "atr_ratchet", args: [TWindow, TScalar, TScalar], ret: TObject([
				{name: "value", ty: TScalar}, {name: "direction", ty: TScalar}
			]), minArgs: 3,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var sm = IndicatorCache.floatArg(args, 1, 4.0);
				var inc = IndicatorCache.floatArg(args, 2, 0.1);
				var key = "atr_ratchet:" + p + ":" + sm + ":" + inc;
				return IndicatorCache.evalBar(h, key, { value: Math.NaN, direction: Math.NaN },
					() -> new AtrRatchet(p, sm, inc), (i, b) -> (cast i : AtrRatchet).update(b));
			}
		};
	}
}
