package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** Equivolume output: price range height and volume-relative width. */
typedef EquivolumeOutput = {
	var height:Float;
	var width:Float;
}

/**
 * Equivolume — ported from wickra-core's `Equivolume`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/equivolume.rs).
 *
 * Richard Arms' charting style: each bar is a "box" whose height is its price
 * range (high - low) and whose width is its volume relative to the period-SMA of volume.
 * A narrow tall box = big range on light volume (easy move); a wide short box =
 * small range on heavy volume (churn).
 */
class Equivolume implements MuseIndicator<Bar, EquivolumeOutput> {
	var period:Int;
	var volSma:Sma;
	var last:Null<EquivolumeOutput>;

	public function new(period:Int) {
		if (period <= 0) throw "Equivolume: period must be > 0";
		this.period = period;
		this.volSma = new Sma(period);
		this.last = null;
	}

	public function update(bar:Bar):Null<EquivolumeOutput> {
		var avgVol = volSma.update(bar.volume);
		if (avgVol == null) return null;

		var height = bar.high - bar.low;
		var width = if (avgVol > 0.0) {
			bar.volume / avgVol;
		} else {
			0.0;
		};

		var out:EquivolumeOutput = { height: height, width: width };
		last = out;
		return out;
	}

	public function reset():Void {
		volSma.reset();
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "Equivolume";

	public static function spec():IndicatorSpec {
		return {
			name: "equivolume", args: [TWindow], ret: TObject([
				{name: "height", ty: TScalar}, {name: "width", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "equivolume:" + p, { height: Math.NaN, width: Math.NaN },
					() -> new Equivolume(p), (i, b) -> (cast i : Equivolume).update(b));
			}
		};
	}
}
