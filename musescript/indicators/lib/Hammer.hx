package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Hammer candlestick pattern — a bullish reversal shape (small body near the
 * top of the range, negligible upper shadow, a lower shadow at least twice
 * the body) that only counts as a "hammer" when it appears after a
 * downtrend context.
 *
 * shape: body <= 0.3*range, upperShadow <= 0.3*range,
 *        lowerShadow >= 2 * max(body, epsilon)
 * context: the bar's low undercuts the lowest close of the preceding
 *          `contextPeriod` bars (confirms a prior downtrend to reverse).
 *
 * Output is 1.0 when both the shape and the downtrend context hold, 0.0
 * otherwise.
 */
class Hammer implements MuseIndicator<Bar, Float> {
	var contextPeriod:Int;
	var closeWindow:Array<Float>;

	public function new(contextPeriod:Int = 5) {
		if (contextPeriod <= 0) throw "Hammer: contextPeriod must be > 0";
		this.contextPeriod = contextPeriod;
		closeWindow = [];
	}

	public function update(bar:Bar):Null<Float> {
		var result = 0.0;
		if (closeWindow.length == contextPeriod) {
			var lowestClose = closeWindow[0];
			for (v in closeWindow) if (v < lowestClose) lowestClose = v;
			if (isHammerShape(bar) && bar.low < lowestClose) result = 1.0;
		}

		if (closeWindow.length == contextPeriod) closeWindow.shift();
		closeWindow.push(bar.close);

		return result;
	}

	static function isHammerShape(bar:Bar):Bool {
		var range = bar.high - bar.low;
		if (range <= 0.0) return false;
		var bodyTop = Math.max(bar.open, bar.close);
		var bodyBottom = Math.min(bar.open, bar.close);
		var body = bodyTop - bodyBottom;
		var upperShadow = bar.high - bodyTop;
		var lowerShadow = bodyBottom - bar.low;
		return body <= 0.3 * range && upperShadow <= 0.3 * range && lowerShadow >= 2.0 * Math.max(body, 1e-12);
	}

	public function reset():Void {
		closeWindow = [];
	}

	public function warmupPeriod():Int return contextPeriod + 1;
	public function isReady():Bool return closeWindow.length == contextPeriod;
	public function name():String return "Hammer";

	public static function spec():IndicatorSpec {
		return {
			name: "hammer", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = args.length > 0 ? IndicatorCache.intArg(args, 0, 5) : 5;
				return IndicatorCache.evalBar(h, "hammer:" + p, Math.NaN,
					() -> new Hammer(p), (i, b) -> (cast i : Hammer).update(b));
			}
		};
	}
}
