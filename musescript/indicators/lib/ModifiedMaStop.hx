package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/**
 * Modified MA Stop: an ATR-offset trailing stop built around a moving
 * average of price (rather than the raw close, as `AtrTrailingStop` uses),
 * ratcheted so it only ever moves in the position's favor.
 *
 * base = SMA(close, maPeriod) - multiplier * ATR(atrPeriod)
 * stop = max(base, previous stop)     (never moves down)
 */
class ModifiedMaStop implements MuseIndicator<Bar, Float> {
	var sma:Sma;
	var atr:Atr;
	var multiplier:Float;
	var stop:Null<Float>;

	public function new(maPeriod:Int, atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "ModifiedMaStop: multiplier must be positive and finite";
		sma = new Sma(maPeriod);
		atr = new Atr(atrPeriod);
		this.multiplier = multiplier;
		stop = null;
	}

	public function update(bar:Bar):Null<Float> {
		var ma = sma.update(bar.close);
		var atrVal = atr.update(bar);
		if (ma == null || atrVal == null) return null;

		var base = ma - multiplier * atrVal;
		stop = stop == null ? base : Math.max(base, stop);
		return stop;
	}

	public function reset():Void {
		sma.reset();
		atr.reset();
		stop = null;
	}

	public function warmupPeriod():Int return Std.int(Math.max(sma.period, atr.period));
	public function isReady():Bool return stop != null;
	public function name():String return "ModifiedMaStop";

	public static function spec():IndicatorSpec {
		return {
			name: "modified_ma_stop", args: [TWindow, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var maPeriod = IndicatorCache.intArg(args, 0, 20);
				var atrPeriod = IndicatorCache.intArg(args, 1, 10);
				var m = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "modified_ma_stop:" + maPeriod + ":" + atrPeriod + ":" + m;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new ModifiedMaStop(maPeriod, atrPeriod, m), (i, b) -> (cast i : ModifiedMaStop).update(b));
			}
		};
	}
}
