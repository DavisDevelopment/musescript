package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** MA Envelope output: the upper/lower percentage bands around the moving average. */
typedef MaEnvelopeOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Moving Average Envelope: fixed-percentage bands around a simple moving
 * average, the simplest volatility-band construction (compare `Bollinger`,
 * whose bands scale with actual stddev instead of a constant percentage).
 *
 * middle = SMA(price, period)
 * upper  = middle * (1 + pct)
 * lower  = middle * (1 - pct)
 */
class MaEnvelope implements MuseIndicator<Float, MaEnvelopeOutput> {
	var sma:Sma;
	var pct:Float;

	public function new(period:Int, pct:Float) {
		if (!Math.isFinite(pct) || pct <= 0.0) throw "MaEnvelope: pct must be positive and finite";
		sma = new Sma(period);
		this.pct = pct;
	}

	public function update(price:Float):Null<MaEnvelopeOutput> {
		var mid = sma.update(price);
		if (mid == null) return null;
		return { upper: mid * (1.0 + pct), middle: mid, lower: mid * (1.0 - pct) };
	}

	public function reset():Void {
		sma.reset();
	}

	public function warmupPeriod():Int return sma.period;
	public function isReady():Bool return sma.isReady();
	public function name():String return "MaEnvelope";

	public static function spec():IndicatorSpec {
		return {
			name: "ma_envelope", args: [TSeries, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var pct = IndicatorCache.floatArg(args, 2, 0.025);
				var key = "ma_envelope:" + series + ":" + p + ":" + pct;
				return IndicatorCache.evalSeries(h, key, series, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new MaEnvelope(p, pct), (i, v) -> (cast i : MaEnvelope).update(v));
			}
		};
	}
}
