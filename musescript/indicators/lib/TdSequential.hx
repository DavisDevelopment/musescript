package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** TD Sequential output: setup count, countdown count, and active countdown direction. */
typedef TdSequentialOutput = {
	/** Signed setup count: +N buy setup, −N sell setup, 0 if neither streak active. Capped at ±9. */
	var setup:Float;
	/** Signed countdown count: +N buy countdown, −N sell countdown, 0 if none active. Capped at ±13. */
	var countdown:Float;
	/** Direction of the active countdown: +1 buy, −1 sell, 0 if none. */
	var direction:Float;
}

/**
 * Tom DeMark TD Sequential (Setup + Countdown) — ported from wickra-core's
 * `TdSequential`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_sequential.rs).
 *
 * Two-phase exhaustion pattern: a 9-bar setup (consecutive closes beyond the
 * close 4 bars earlier) arms a 13-bar countdown (bars whose close is beyond
 * the high/low 2 bars earlier, not necessarily consecutive). A completed
 * countdown is the canonical DeMark reversal signal. An opposite-direction
 * setup completion invalidates the active countdown.
 */
class TdSequential implements MuseIndicator<Bar, TdSequentialOutput> {
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
	var countdownDir:Int;
	var ready:Bool;

	public function new(setupLookback:Int, setupTarget:Int, countdownLookback:Int, countdownTarget:Int) {
		if (setupLookback <= 0 || setupTarget <= 0 || countdownLookback <= 0 || countdownTarget <= 0)
			throw "TdSequential: all periods must be > 0";
		this.setupLookback = setupLookback;
		this.setupTarget = setupTarget;
		this.countdownLookback = countdownLookback;
		this.countdownTarget = countdownTarget;
		reset();
	}

	/** DeMark's classic configuration: setup `4, 9`, countdown `2, 13`. */
	public static function classic():TdSequential {
		return new TdSequential(4, 9, 2, 13);
	}

	/** Configured `[setupLookback, setupTarget, countdownLookback, countdownTarget]`. */
	public function params():Array<Int> {
		return [setupLookback, setupTarget, countdownLookback, countdownTarget];
	}

	inline function need():Int {
		return setupLookback > countdownLookback ? setupLookback : countdownLookback;
	}

	public function update(bar:Bar):Null<TdSequentialOutput> {
		var n = need();
		// Warmup: need `n` prior bars before evaluating.
		if (candles.length < n) {
			candles.push(bar);
			return null;
		}

		// Eviction-before-read: when capacity already holds `n+1` prior+current
		// from the previous bar, the prior-`n` slice starts at oldest(1).
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
			if (countdownDir != DIR_BUY) {
				buyCountdown = 0;
				sellCountdown = 0;
			}
			countdownDir = DIR_BUY;
		} else if (sellSetup == setupTarget) {
			if (countdownDir != DIR_SELL) {
				buyCountdown = 0;
				sellCountdown = 0;
			}
			countdownDir = DIR_SELL;
		}

		var cdRef = candles.oldest(base + n - countdownLookback);
		switch (countdownDir) {
			case DIR_BUY:
				if (bar.close <= cdRef.low && buyCountdown < countdownTarget) buyCountdown++;
			case DIR_SELL:
				if (bar.close >= cdRef.high && sellCountdown < countdownTarget) sellCountdown++;
			default:
		}

		candles.push(bar);
		ready = true;

		var setup:Float = if (buySetup > 0) buySetup else if (sellSetup > 0) -sellSetup else 0.0;
		var countdown:Float;
		var direction:Float;
		switch (countdownDir) {
			case DIR_BUY:
				countdown = buyCountdown;
				direction = 1.0;
			case DIR_SELL:
				countdown = -sellCountdown;
				direction = -1.0;
			default:
				countdown = 0.0;
				direction = 0.0;
		}

		return {setup: setup, countdown: countdown, direction: direction};
	}

	public function reset():Void {
		candles = new RingBuffer(need() + 1);
		buySetup = 0;
		sellSetup = 0;
		buyCountdown = 0;
		sellCountdown = 0;
		countdownDir = DIR_NONE;
		ready = false;
	}

	public function warmupPeriod():Int {
		return need() + 1;
	}

	public function isReady():Bool return ready;
	public function name():String return "TDSequential";

	public static function spec():IndicatorSpec {
		return {
			name: "td_sequential", args: [TWindow, TWindow, TWindow, TWindow], ret: TObject([
				{name: "setup", ty: TScalar}, {name: "countdown", ty: TScalar}, {name: "direction", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var sl = IndicatorCache.intArg(args, 0, 4);
				var st = IndicatorCache.intArg(args, 1, 9);
				var cl = IndicatorCache.intArg(args, 2, 2);
				var ct = IndicatorCache.intArg(args, 3, 13);
				var key = "td_sequential:" + sl + ":" + st + ":" + cl + ":" + ct;
				var nanFill:TdSequentialOutput = {setup: Math.NaN, countdown: Math.NaN, direction: Math.NaN};
				return IndicatorCache.evalBar(h, key, nanFill,
					() -> new TdSequential(sl, st, cl, ct), (i, b) -> (cast i : TdSequential).update(b));
			}
		};
	}
}
