package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Morning/Evening Star candlestick pattern — the general "star" reversal
 * family: a strong trend bar, a small-bodied "star" bar that gaps away from
 * it (not necessarily a doji — see `MorningDojiStar`/`EveningDojiStar` for
 * the doji-specific variants), then a strong bar reversing back into the
 * first bar's body.
 *
 * star threshold: |bar2 body| <= 0.3 * |bar1 body| (small relative to the
 *                 trend bar, looser than the doji-tolerance variants)
 *
 * bullish/morning (+1.0): bar1 red, bar2 gaps down and is a star, bar3
 *                 green and closes above bar1's body midpoint.
 * bearish/evening (-1.0): bar1 green, bar2 gaps up and is a star, bar3 red
 *                 and closes below bar1's body midpoint.
 *
 * Output is 0.0 otherwise.
 */
class MorningEveningStar implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;

	public function new() {
		prev = null;
		prevPrev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var pp = prevPrev;
		var p = prev;
		prevPrev = prev;
		prev = bar;

		if (pp == null || p == null) return pp == null && p == null ? null : 0.0;
		return compute(pp, p, bar);
	}

	static function compute(bar1:Bar, bar2:Bar, bar3:Bar):Float {
		var body1 = Math.abs(bar1.close - bar1.open);
		if (body1 <= 0.0) return 0.0;
		var body2 = Math.abs(bar2.close - bar2.open);
		if (body2 > 0.3 * body1) return 0.0; // bar2 must be a "star" (small body)

		var bar1BodyMid = (bar1.open + bar1.close) / 2.0;

		if (bar1.close < bar1.open
			&& bar2.high < bar1.close
			&& bar3.close > bar3.open
			&& bar3.close > bar1BodyMid) {
			return 1.0;
		}
		if (bar1.close > bar1.open
			&& bar2.low > bar1.close
			&& bar3.close < bar3.open
			&& bar3.close < bar1BodyMid) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return prev != null && prevPrev != null;
	public function name():String return "MorningEveningStar";

	public static function spec():IndicatorSpec {
		return {
			name: "morning_evening_star", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "morning_evening_star", Math.NaN,
				() -> new MorningEveningStar(), (i, b) -> (cast i : MorningEveningStar).update(b))
		};
	}
}
