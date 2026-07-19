package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** NRTR output: the current stop/reversal level and trend direction (+1/-1). */
typedef NrtrOutput = {
	var level:Float;
	var direction:Float;
}

/**
 * NRTR (Nick Rypock Trailing Reverse): a percentage-based trailing stop
 * that flips direction — and resets its trailing extreme — whenever price
 * crosses it, rather than only ratcheting one way forever like
 * `AtrTrailingStop`.
 *
 * uptrend:   extreme = running max(price) since the last flip
 *            level   = extreme * (1 - pct)
 *            flips to downtrend when price < level
 * downtrend: extreme = running min(price) since the last flip
 *            level   = extreme * (1 + pct)
 *            flips to uptrend when price > level
 *
 * Starts in the uptrend state on the first bar (a defensible, documented
 * default — there's no prior trend to inherit).
 */
class Nrtr implements MuseIndicator<Float, NrtrOutput> {
	var pct:Float;
	var uptrend:Bool;
	var extreme:Null<Float>;

	public function new(pct:Float) {
		if (!Math.isFinite(pct) || pct <= 0.0 || pct >= 1.0) throw "Nrtr: pct must be in (0, 1)";
		this.pct = pct;
		uptrend = true;
		extreme = null;
	}

	public function update(price:Float):Null<NrtrOutput> {
		if (!Math.isFinite(price)) return null;
		if (extreme == null) {
			extreme = price;
			return { level: price * (1.0 - pct), direction: 1.0 };
		}

		if (uptrend) {
			if (price > extreme) extreme = price;
			var level = extreme * (1.0 - pct);
			if (price < level) {
				uptrend = false;
				extreme = price;
				level = extreme * (1.0 + pct);
			}
			return { level: level, direction: uptrend ? 1.0 : -1.0 };
		} else {
			if (price < extreme) extreme = price;
			var level = extreme * (1.0 + pct);
			if (price > level) {
				uptrend = true;
				extreme = price;
				level = extreme * (1.0 - pct);
			}
			return { level: level, direction: uptrend ? 1.0 : -1.0 };
		}
	}

	public function reset():Void {
		uptrend = true;
		extreme = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return extreme != null;
	public function name():String return "Nrtr";

	public static function spec():IndicatorSpec {
		return {
			name: "nrtr", args: [TSeries, TScalar], ret: TObject([
				{name: "level", ty: TScalar}, {name: "direction", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var pct = IndicatorCache.floatArg(args, 1, 0.05);
				return IndicatorCache.evalSeries(h, "nrtr:" + series + ":" + pct, series, { level: Math.NaN, direction: Math.NaN },
					() -> new Nrtr(pct), (i, v) -> (cast i : Nrtr).update(v));
			}
		};
	}
}
