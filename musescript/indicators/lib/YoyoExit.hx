package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/**
 * Yo-Yo Exit — ported from wickra-core's `YoyoExit`
 * (vendor/wickra/crates/wickra-core/src/indicators/yoyo_exit.rs).
 *
 * An ATR-based long-only trailing stop that "yo-yos" in and out of the
 * market: when price closes below the trail it exits; when price recovers
 * `multiplier · ATR` above the same trail it re-enters long. The emitted
 * level is always the trail itself:
 *
 *   band = multiplier · ATR
 *   in-trade: trail_t = max(trail_{t−1}, close − band); exit on close < trail
 *   out:      trail held flat; re-enter when close > trail + band
 *
 * Common configuration: ATR(14) × 2.0.
 */
class YoyoExit implements MuseIndicator<Bar, Float> {
	var atr:Atr;
	var atrPeriod:Int;
	var multiplier:Float;
	var trail:Null<Float>;
	/** true while the trail is being ratcheted; false while sidelined. */
	var inTradeFlag:Bool;

	public function new(atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "YoyoExit: multiplier must be positive and finite";
		atr = new Atr(atrPeriod);
		this.atrPeriod = atrPeriod;
		this.multiplier = multiplier;
		trail = null;
		inTradeFlag = true;
	}

	/** A common configuration: ATR(14) with a 2.0 multiplier. */
	public static function classic():YoyoExit {
		return new YoyoExit(14, 2.0);
	}

	/** true while the strategy is currently long, false while sidelined. */
	public function inTrade():Bool return inTradeFlag;

	public function update(bar:Bar):Null<Float> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;
		var band = multiplier * atrVal;
		var close = bar.close;

		var newTrail:Float;
		if (trail != null) {
			var prev:Float = trail;
			if (inTradeFlag) {
				if (close < prev) {
					// Stopped out — sideline, keep the trail flat.
					inTradeFlag = false;
					newTrail = prev;
				} else {
					// Ratchet up only.
					newTrail = Math.max(prev, close - band);
				}
			} else if (close > prev + band) {
				// Re-entry trigger — start a new trail anchored on this close.
				inTradeFlag = true;
				newTrail = close - band;
			} else {
				newTrail = prev;
			}
		} else {
			// First ATR-ready bar starts a fresh long.
			newTrail = close - band;
		}
		trail = newTrail;
		return newTrail;
	}

	public function reset():Void {
		atr.reset();
		trail = null;
		inTradeFlag = true;
	}

	public function warmupPeriod():Int return atrPeriod;
	public function isReady():Bool return trail != null;
	public function name():String return "YoyoExit";

	public static function spec():IndicatorSpec {
		return {
			name: "yoyo_exit", args: [TWindow, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var m = IndicatorCache.floatArg(args, 1, 2.0);
				var key = "yoyo_exit:" + p + ":" + m;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new YoyoExit(p, m), (i, b) -> (cast i : YoyoExit).update(b));
			}
		};
	}
}
