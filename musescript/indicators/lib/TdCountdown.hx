package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Countdown (standalone 13-bar countdown) — ported from
 * wickra-core's `TdCountdown`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_countdown.rs).
 *
 * Runs the setup-detection phase internally (9 consecutive closes beyond the
 * close `setupLookback` bars earlier) and exposes only the countdown count:
 * a buy countdown advances on bars where `close <= low[countdownLookback
 * bars ago]` (need not be consecutive), a sell countdown on `close >=
 * high[countdownLookback bars ago]`; each saturates at `countdownTarget`.
 * An opposite-direction setup completion invalidates the active countdown.
 * Output is signed: positive buy countdown, negative sell countdown, 0 when
 * no countdown is armed.
 */
class TdCountdown implements MuseIndicator<Bar, Float> {
	static inline var DIR_NONE = 0;
	static inline var DIR_BUY = 1;
	static inline var DIR_SELL = -1;

	var setupLookback:Int;
	var setupTarget:Int;
	var countdownLookback:Int;
	var countdownTarget:Int;
	var candles:RingBuffer<Bar>;
	var buySetup:Int;
	var sellSetup:Int;
	var buyCountdown:Int;
	var sellCountdown:Int;
	var direction:Int;
	var ready:Bool;

	public function new(setupLookback:Int, setupTarget:Int, countdownLookback:Int, countdownTarget:Int) {
		if (setupLookback <= 0 || setupTarget <= 0 || countdownLookback <= 0 || countdownTarget <= 0)
			throw "TdCountdown: all periods must be > 0";
		this.setupLookback = setupLookback;
		this.setupTarget = setupTarget;
		this.countdownLookback = countdownLookback;
		this.countdownTarget = countdownTarget;
		reset();
	}

	/** DeMark's classic configuration: setup `4, 9`, countdown `2, 13`. */
	public static function classic():TdCountdown {
		return new TdCountdown(4, 9, 2, 13);
	}

	/** Configured `[setupLookback, setupTarget, countdownLookback, countdownTarget]`. */
	public function params():Array<Int> {
		return [setupLookback, setupTarget, countdownLookback, countdownTarget];
	}

	inline function need():Int {
		return setupLookback > countdownLookback ? setupLookback : countdownLookback;
	}

	public function update(bar:Bar):Null<Float> {
		var n = need();
		if (candles.length < n) {
			candles.push(bar);
			return null;
		}

		var base = candles.length - n;
		var setupRefClose = candles.oldest(base + n - setupLookback).close;
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

		if (buySetup == setupTarget) {
			if (direction != DIR_BUY) {
				buyCountdown = 0;
				sellCountdown = 0;
			}
			direction = DIR_BUY;
		} else if (sellSetup == setupTarget) {
			if (direction != DIR_SELL) {
				buyCountdown = 0;
				sellCountdown = 0;
			}
			direction = DIR_SELL;
		}

		var cdRef = candles.oldest(base + n - countdownLookback);
		switch (direction) {
			case DIR_BUY:
				if (bar.close <= cdRef.low && buyCountdown < countdownTarget) buyCountdown++;
			case DIR_SELL:
				if (bar.close >= cdRef.high && sellCountdown < countdownTarget) sellCountdown++;
			default:
		}

		candles.push(bar);
		ready = true;

		return switch (direction) {
			case DIR_BUY: (buyCountdown : Float);
			case DIR_SELL: -(sellCountdown : Float);
			default: 0.0;
		};
	}

	public function reset():Void {
		candles = new RingBuffer(need() + 1);
		buySetup = 0;
		sellSetup = 0;
		buyCountdown = 0;
		sellCountdown = 0;
		direction = DIR_NONE;
		ready = false;
	}

	public function warmupPeriod():Int {
		return need() + 1;
	}

	public function isReady():Bool return ready;
	public function name():String return "TDCountdown";

	public static function spec():IndicatorSpec {
		return {
			name: "td_countdown", args: [TWindow, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var sl = IndicatorCache.intArg(args, 0, 4);
				var st = IndicatorCache.intArg(args, 1, 9);
				var cl = IndicatorCache.intArg(args, 2, 2);
				var ct = IndicatorCache.intArg(args, 3, 13);
				var key = "td_countdown:" + sl + ":" + st + ":" + cl + ":" + ct;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new TdCountdown(sl, st, cl, ct), (i, b) -> (cast i : TdCountdown).update(b));
			}
		};
	}
}
