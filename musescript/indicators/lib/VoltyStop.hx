package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/**
 * Volty Stop (Volatility Stop, Kase) — ported from wickra-core's `VoltyStop`
 * (vendor/wickra/crates/wickra-core/src/indicators/volty_stop.rs).
 *
 * A volatility-anchored trailing stop hung off the EXTREME close recorded
 * since the current trade opened (not off the most recent bar):
 *
 *   long:  anchor = max close since long;  stop = anchor − multiplier · ATR
 *          flip-to-short on close < stop → anchor = close
 *   short: anchor = min close since short; stop = anchor + multiplier · ATR
 *          flip-to-long  on close > stop → anchor = close
 *
 * The anchor only ratchets in the trade's favour, so the stop tightens as
 * price reaches new extremes. Common configuration: ATR(14) × 2.0.
 */
class VoltyStop implements MuseIndicator<Bar, Float> {
	var atr:Atr;
	var atrPeriod:Int;
	var multiplier:Float;
	var anchor:Null<Float>;
	var long:Bool;

	public function new(atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "VoltyStop: multiplier must be positive and finite";
		atr = new Atr(atrPeriod);
		this.atrPeriod = atrPeriod;
		this.multiplier = multiplier;
		anchor = null;
		long = true;
	}

	/** A common configuration: ATR(14) with a 2.0 multiplier. */
	public static function classic():VoltyStop {
		return new VoltyStop(14, 2.0);
	}

	public function update(bar:Bar):Null<Float> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;
		var band = multiplier * atrVal;
		var close = bar.close;

		if (anchor != null) {
			var prevAnchor:Float = anchor;
			if (long) {
				var stopLevel = prevAnchor - band;
				if (close < stopLevel) {
					// Close-through long stop -> flip short, anchor at close.
					anchor = close;
					long = false;
				} else {
					// Ratchet the anchor up to today's close if higher.
					anchor = Math.max(prevAnchor, close);
				}
			} else {
				var stopLevel = prevAnchor + band;
				if (close > stopLevel) {
					anchor = close;
					long = true;
				} else {
					anchor = Math.min(prevAnchor, close);
				}
			}
		} else {
			// First ATR-ready bar seeds a long anchor at the close.
			anchor = close;
			long = true;
		}
		return long ? anchor - band : anchor + band;
	}

	public function reset():Void {
		atr.reset();
		anchor = null;
		long = true;
	}

	public function warmupPeriod():Int return atrPeriod;
	public function isReady():Bool return anchor != null;
	public function name():String return "VoltyStop";

	public static function spec():IndicatorSpec {
		return {
			name: "volty_stop", args: [TWindow, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var m = IndicatorCache.floatArg(args, 1, 2.0);
				var key = "volty_stop:" + p + ":" + m;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new VoltyStop(p, m), (i, b) -> (cast i : VoltyStop).update(b));
			}
		};
	}
}
