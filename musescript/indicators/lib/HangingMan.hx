package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Hanging Man candlestick pattern — geometrically identical to `Hammer`
 * (small body near the top, negligible upper shadow, long lower shadow),
 * but bearish: it only counts as a "hanging man" when it appears after an
 * *uptrend* context, where the same shape warns of exhaustion rather than
 * signalling a bottom.
 *
 * shape: same as `Hammer`.
 * context: the bar's high exceeds the highest close of the preceding
 *          `contextPeriod` bars (confirms a prior uptrend to reverse).
 *
 * Output is -1.0 when both the shape and the uptrend context hold, 0.0
 * otherwise.
 */
class HangingMan implements MuseIndicator<Bar, Float> {
	var contextPeriod:Int;
	var closeWindow:RingBuffer<Float>;

	public function new(contextPeriod:Int = 5) {
		if (contextPeriod <= 0) throw "HangingMan: contextPeriod must be > 0";
		this.contextPeriod = contextPeriod;
		closeWindow = new RingBuffer(contextPeriod);
	}

	public function update(bar:Bar):Null<Float> {
		var result = 0.0;
		if (closeWindow.length == contextPeriod) {
			var highestClose = closeWindow.oldest(0);
			for (v in closeWindow) if (v > highestClose) highestClose = v;
			if (isHangingManShape(bar) && bar.high > highestClose) result = -1.0;
		}

		closeWindow.push(bar.close);

		return result;
	}

	static function isHangingManShape(bar:Bar):Bool {
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
		closeWindow = new RingBuffer(contextPeriod);
	}

	public function warmupPeriod():Int return contextPeriod + 1;
	public function isReady():Bool return closeWindow.length == contextPeriod;
	public function name():String return "HangingMan";

	public static function spec():IndicatorSpec {
		return {
			name: "hanging_man", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = args.length > 0 ? IndicatorCache.intArg(args, 0, 5) : 5;
				return IndicatorCache.evalBar(h, "hanging_man:" + p, Math.NaN,
					() -> new HangingMan(p), (i, b) -> (cast i : HangingMan).update(b));
			}
		};
	}
}
