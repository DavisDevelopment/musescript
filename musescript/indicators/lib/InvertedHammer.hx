package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Inverted Hammer candlestick pattern — the shape mirror of `Hammer` (small
 * body near the *bottom* of the range, negligible lower shadow, a long
 * upper shadow at least twice the body), appearing after a downtrend
 * context, signalling a potential bullish reversal.
 *
 * shape: body <= 0.3*range, lowerShadow <= 0.3*range,
 *        upperShadow >= 2 * max(body, epsilon)
 * context: the bar's low undercuts the lowest close of the preceding
 *          `contextPeriod` bars.
 *
 * Output is 1.0 when both the shape and the downtrend context hold, 0.0
 * otherwise.
 */
class InvertedHammer implements MuseIndicator<Bar, Float> {
	var contextPeriod:Int;
	var closeWindow:Array<Float>;

	public function new(contextPeriod:Int = 5) {
		if (contextPeriod <= 0) throw "InvertedHammer: contextPeriod must be > 0";
		this.contextPeriod = contextPeriod;
		closeWindow = [];
	}

	public function update(bar:Bar):Null<Float> {
		var result = 0.0;
		if (closeWindow.length == contextPeriod) {
			var lowestClose = closeWindow[0];
			for (v in closeWindow) if (v < lowestClose) lowestClose = v;
			if (isInvertedHammerShape(bar) && bar.low < lowestClose) result = 1.0;
		}

		if (closeWindow.length == contextPeriod) closeWindow.shift();
		closeWindow.push(bar.close);

		return result;
	}

	static function isInvertedHammerShape(bar:Bar):Bool {
		var range = bar.high - bar.low;
		if (range <= 0.0) return false;
		var bodyTop = Math.max(bar.open, bar.close);
		var bodyBottom = Math.min(bar.open, bar.close);
		var body = bodyTop - bodyBottom;
		var upperShadow = bar.high - bodyTop;
		var lowerShadow = bodyBottom - bar.low;
		return body <= 0.3 * range && lowerShadow <= 0.3 * range && upperShadow >= 2.0 * Math.max(body, 1e-12);
	}

	public function reset():Void {
		closeWindow = [];
	}

	public function warmupPeriod():Int return contextPeriod + 1;
	public function isReady():Bool return closeWindow.length == contextPeriod;
	public function name():String return "InvertedHammer";

	public static function spec():IndicatorSpec {
		return {
			name: "inverted_hammer", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = args.length > 0 ? IndicatorCache.intArg(args, 0, 5) : 5;
				return IndicatorCache.evalBar(h, "inverted_hammer:" + p, Math.NaN,
					() -> new InvertedHammer(p), (i, b) -> (cast i : InvertedHammer).update(b));
			}
		};
	}
}
