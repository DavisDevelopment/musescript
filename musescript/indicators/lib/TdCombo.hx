package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Combo (aggressive countdown variant) — ported from
 * wickra-core's `TdCombo`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_combo.rs).
 *
 * Like the vanilla countdown, the combo is armed by a completed 9-bar setup
 * in the same direction, but each combo bar must additionally satisfy two
 * strictness conditions: a buy-combo bar needs `close <= low[-2]`,
 * `low <= low[-1]`, and `close < close[-1]` (sell mirrors with highs and
 * strictly-higher closes). Saturates at `countdownTarget`. Output is signed:
 * positive buy combo, negative sell combo, 0 when not armed.
 */
class TdCombo implements MuseIndicator<Bar, Float> {
	static inline var DIR_NONE = 0;
	static inline var DIR_BUY = 1;
	static inline var DIR_SELL = -1;

	var setupLookback:Int;
	var setupTarget:Int;
	var countdownLookback:Int;
	var countdownTarget:Int;
	var candles:Array<Bar>;
	var buySetup:Int;
	var sellSetup:Int;
	var buyCombo:Int;
	var sellCombo:Int;
	var direction:Int;
	var ready:Bool;

	public function new(setupLookback:Int, setupTarget:Int, countdownLookback:Int, countdownTarget:Int) {
		if (setupLookback <= 0 || setupTarget <= 0 || countdownLookback <= 0 || countdownTarget <= 0)
			throw "TdCombo: all periods must be > 0";
		this.setupLookback = setupLookback;
		this.setupTarget = setupTarget;
		this.countdownLookback = countdownLookback;
		this.countdownTarget = countdownTarget;
		candles = [];
		buySetup = 0;
		sellSetup = 0;
		buyCombo = 0;
		sellCombo = 0;
		direction = DIR_NONE;
		ready = false;
	}

	/** DeMark's classic configuration: setup `4, 9`, combo `2, 13`. */
	public static function classic():TdCombo {
		return new TdCombo(4, 9, 2, 13);
	}

	/** Configured `[setupLookback, setupTarget, countdownLookback, countdownTarget]`. */
	public function params():Array<Int> {
		return [setupLookback, setupTarget, countdownLookback, countdownTarget];
	}

	public function update(bar:Bar):Null<Float> {
		var need = setupLookback > countdownLookback ? setupLookback : countdownLookback;
		var cap = need + 1;
		if (candles.length == cap) candles.shift();
		if (candles.length < need) {
			candles.push(bar);
			return null;
		}

		// Setup rule: compare to close[setupLookback bars ago].
		var setupRefClose = candles[need - setupLookback].close;
		if (bar.close < setupRefClose) {
			buySetup = buySetup + 1 < setupTarget ? buySetup + 1 : setupTarget;
			sellSetup = 0;
		} else if (bar.close > setupRefClose) {
			sellSetup = sellSetup + 1 < setupTarget ? sellSetup + 1 : setupTarget;
			buySetup = 0;
		} else {
			buySetup = 0;
			sellSetup = 0;
		}

		// Combo arming: a completed setup in either direction arms the combo
		// in the same direction (resetting any opposite-direction count first).
		if (buySetup == setupTarget) {
			if (direction != DIR_BUY) {
				buyCombo = 0;
				sellCombo = 0;
			}
			direction = DIR_BUY;
		} else if (sellSetup == setupTarget) {
			if (direction != DIR_SELL) {
				buyCombo = 0;
				sellCombo = 0;
			}
			direction = DIR_SELL;
		}

		// Combo rule references the candle `countdownLookback` bars ago
		// (high/low) and the immediately-prior candle (monotone strictness).
		var comboRef = candles[need - countdownLookback];
		var prev = candles[need - 1];
		switch (direction) {
			case DIR_BUY:
				var condClassic = bar.close <= comboRef.low;
				var condLow = bar.low <= prev.low;
				var condClose = bar.close < prev.close;
				if (condClassic && condLow && condClose && buyCombo < countdownTarget) buyCombo++;
			case DIR_SELL:
				var condClassic = bar.close >= comboRef.high;
				var condHigh = bar.high >= prev.high;
				var condClose = bar.close > prev.close;
				if (condClassic && condHigh && condClose && sellCombo < countdownTarget) sellCombo++;
			default:
		}

		candles.push(bar);
		ready = true;

		return switch (direction) {
			case DIR_BUY: (buyCombo : Float);
			case DIR_SELL: -(sellCombo : Float);
			default: 0.0;
		};
	}

	public function reset():Void {
		candles = [];
		buySetup = 0;
		sellSetup = 0;
		buyCombo = 0;
		sellCombo = 0;
		direction = DIR_NONE;
		ready = false;
	}

	public function warmupPeriod():Int {
		return (setupLookback > countdownLookback ? setupLookback : countdownLookback) + 1;
	}

	public function isReady():Bool return ready;
	public function name():String return "TDCombo";

	public static function spec():IndicatorSpec {
		return {
			name: "td_combo", args: [TWindow, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var sl = IndicatorCache.intArg(args, 0, 4);
				var st = IndicatorCache.intArg(args, 1, 9);
				var cl = IndicatorCache.intArg(args, 2, 2);
				var ct = IndicatorCache.intArg(args, 3, 13);
				var key = "td_combo:" + sl + ":" + st + ":" + cl + ":" + ct;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new TdCombo(sl, st, cl, ct), (i, b) -> (cast i : TdCombo).update(b));
			}
		};
	}
}
