package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/**
 * ATR Trailing Stop — ported from wickra-core's `AtrTrailingStop`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/atr_trailing_stop.rs).
 *
 * A stop level that trails price by a fixed ATR multiple and ratchets in the
 * direction of the trend. While price stays on one side of the stop the level
 * only ratchets toward price — up in an uptrend, down in a downtrend. When
 * a close crosses the stop the level snaps to the opposite side, flipping the trade.
 *
 * loss = multiplier · ATR
 * stop_t = max(stop_{t−1}, close − loss)   while price holds above the stop
 *        = min(stop_{t−1}, close + loss)   while price holds below the stop
 *        = close − loss                   on a fresh break above the stop
 *        = close + loss                   on a fresh break below the stop
 */
class AtrTrailingStop implements MuseIndicator<Bar, Float> {
	var atr:Atr;
	var multiplier:Float;
	var atrPeriod:Int;
	var prevClose:Null<Float>;
	var prevStop:Null<Float>;

	public function new(atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "AtrTrailingStop: multiplier must be positive and finite";
		this.atr = new Atr(atrPeriod);
		this.multiplier = multiplier;
		this.atrPeriod = atrPeriod;
		prevClose = null;
		prevStop = null;
	}

	public function update(bar:Bar):Null<Float> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;

		var loss = multiplier * atrVal;
		var close = bar.close;

		var stop:Float;
		if (prevStop != null && prevClose != null) {
			var ps = prevStop;
			var pc = prevClose;

			if (close > ps && pc > ps) {
				// Holding above the stop — ratchet it up only.
				stop = Math.max(close - loss, ps);
			} else if (close < ps && pc < ps) {
				// Holding below the stop — ratchet it down only.
				stop = Math.min(close + loss, ps);
			} else if (close > ps) {
				// Fresh break above — place the stop below the new close.
				stop = close - loss;
			} else {
				// Fresh break below — place the stop above the new close.
				stop = close + loss;
			}
		} else {
			// First ATR-ready bar: seed the stop below price (a long).
			stop = close - loss;
		}

		prevClose = close;
		prevStop = stop;
		return stop;
	}

	public function reset():Void {
		atr.reset();
		prevClose = null;
		prevStop = null;
	}

	public function warmupPeriod():Int return atrPeriod;
	public function isReady():Bool return prevStop != null;
	public function name():String return "AtrTrailingStop";

	public static function spec():IndicatorSpec {
		return {
			name: "atr_trailing_stop", args: [TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var m = IndicatorCache.floatArg(args, 1, 3.0);
				var key = "atr_trailing_stop:" + p + ":" + m;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new AtrTrailingStop(p, m), (i, b) -> (cast i : AtrTrailingStop).update(b));
			}
		};
	}
}
