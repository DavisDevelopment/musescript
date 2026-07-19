package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/** Elder Ray output: bull power and bear power. */
typedef ElderRayOutput = {
	var bull:Float;
	var bear:Float;
}

/**
 * Elder Ray: measures how far buyers pushed price above (bull power) and
 * sellers pushed price below (bear power) a trend-following EMA of close.
 *
 * ema   = EMA(close, period)
 * bull  = high - ema
 * bear  = low - ema
 */
class ElderRay implements MuseIndicator<Bar, ElderRayOutput> {
	var ema:Ema;

	public function new(period:Int) {
		ema = new Ema(period);
	}

	public function update(bar:Bar):Null<ElderRayOutput> {
		var e = ema.update(bar.close);
		if (e == null) return null;
		return { bull: bar.high - e, bear: bar.low - e };
	}

	public function reset():Void {
		ema.reset();
	}

	public function warmupPeriod():Int return ema.period;
	public function isReady():Bool return ema.isReady();
	public function name():String return "ElderRay";

	public static function spec():IndicatorSpec {
		return {
			name: "elder_ray", args: [TWindow], ret: TObject([
				{name: "bull", ty: TScalar}, {name: "bear", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 13);
				return IndicatorCache.evalBar(h, "elder_ray:" + p, { bull: Math.NaN, bear: Math.NaN },
					() -> new ElderRay(p), (i, b) -> (cast i : ElderRay).update(b));
			}
		};
	}
}
