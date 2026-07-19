package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** Hurst Channel output: upper/middle/lower bands. */
typedef HurstChannelOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Hurst Channel: an ATR-band envelope whose width scales with the series'
 * own `HurstExponent` estimate — the theoretical scaling-law relationship
 * `range ~ ATR * period^H` (a trending, H > 0.5 series widens its channel
 * faster with time than a mean-reverting, H < 0.5 one).
 *
 * middle = SMA(close, period)   (via a simple running mean, tracked directly)
 * width  = ATR(period) * period^HurstExponent(period)
 * upper  = middle + width
 * lower  = middle - width
 */
class HurstChannel implements MuseIndicator<Bar, HurstChannelOutput> {
	var period:Int;
	var atr:Atr;
	var hurst:HurstExponent;
	var closeWindow:Array<Float>;
	var sum:Float;

	public function new(period:Int) {
		if (period < 4) throw "HurstChannel: period must be >= 4";
		this.period = period;
		atr = new Atr(period);
		hurst = new HurstExponent(period);
		closeWindow = [];
		sum = 0.0;
	}

	public function update(bar:Bar):Null<HurstChannelOutput> {
		var atrVal = atr.update(bar);
		var h = hurst.update(bar.close);

		if (closeWindow.length == period) sum -= closeWindow.shift();
		closeWindow.push(bar.close);
		sum += bar.close;

		if (atrVal == null || h == null || closeWindow.length < period) return null;

		var middle = sum / period;
		var width = atrVal * Math.pow(period, h);
		return { upper: middle + width, middle: middle, lower: middle - width };
	}

	public function reset():Void {
		atr.reset();
		hurst.reset();
		closeWindow = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return closeWindow.length == period && atr.isReady() && hurst.isReady();
	public function name():String return "HurstChannel";

	public static function spec():IndicatorSpec {
		return {
			name: "hurst_channel", args: [TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "hurst_channel:" + p, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new HurstChannel(p), (i, b) -> (cast i : HurstChannel).update(b));
			}
		};
	}
}
