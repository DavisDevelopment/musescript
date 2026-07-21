package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/** Volume-Weighted MACD output: the three classic MACD series. */
typedef VolumeWeightedMacdOutput = {
	var macd:Float;
	var signal:Float;
	var histogram:Float;
}

/**
 * Volume-Weighted MACD — ported from wickra-core's `VolumeWeightedMacd`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/volume_weighted_macd.rs).
 *
 *   macd      = VWMA(close, fast) - VWMA(close, slow)
 *   signal    = EMA(macd, signalPeriod)
 *   histogram = macd - signal
 *
 * The volume-weighted variant replaces each MACD average with a VWMA, so
 * heavy-volume bars dominate the trend estimate; the signal line keeps a
 * standard EMA. First output lands after `slow + signal - 1` inputs.
 */
class VolumeWeightedMacd implements MuseIndicator<Bar, VolumeWeightedMacdOutput> {
	var fast:Vwma;
	var slow:Vwma;
	var signalEma:Ema;
	var fastPeriod:Int;
	var slowPeriod:Int;
	var signalPeriod:Int;
	var last:Null<VolumeWeightedMacdOutput>;

	public function new(fast:Int, slow:Int, signal:Int) {
		if (fast <= 0 || slow <= 0 || signal <= 0) throw "VolumeWeightedMacd: periods must be > 0";
		if (fast >= slow) throw "VolumeWeightedMacd: fast period must be strictly less than slow period";
		this.fast = new Vwma(fast);
		this.slow = new Vwma(slow);
		this.signalEma = new Ema(signal);
		this.fastPeriod = fast;
		this.slowPeriod = slow;
		this.signalPeriod = signal;
		this.last = null;
	}

	/** Configured periods. */
	public function periods():{fast:Int, slow:Int, signal:Int}
		return {fast: fastPeriod, slow: slowPeriod, signal: signalPeriod};

	/** Most recent fully-computed output if available. */
	public function value():Null<VolumeWeightedMacdOutput> return last;

	public function update(bar:Bar):Null<VolumeWeightedMacdOutput> {
		var f = fast.update(bar);
		var s = slow.update(bar);
		if (f != null && s != null) {
			var macd = f - s;
			var signal = signalEma.update(macd);
			if (signal == null) return null;
			var out:VolumeWeightedMacdOutput = {
				macd: macd,
				signal: signal,
				histogram: macd - signal
			};
			last = out;
			return out;
		}
		return null;
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
		signalEma.reset();
		last = null;
	}

	public function warmupPeriod():Int return slowPeriod + signalPeriod - 1;
	public function isReady():Bool return last != null;
	public function name():String return "VolumeWeightedMacd";

	public static function spec():IndicatorSpec {
		return {
			name: "volume_weighted_macd", args: [TWindow, TWindow, TWindow], ret: TObject([
				{name: "macd", ty: TScalar}, {name: "signal", ty: TScalar}, {name: "histogram", ty: TScalar}
			]), minArgs: 3,
			eval: function(h, args) {
				var fast = IndicatorCache.intArg(args, 0, 12);
				var slow = IndicatorCache.intArg(args, 1, 26);
				var signal = IndicatorCache.intArg(args, 2, 9);
				var nanFill:VolumeWeightedMacdOutput = {macd: Math.NaN, signal: Math.NaN, histogram: Math.NaN};
				return IndicatorCache.evalBar(h, "volume_weighted_macd:" + fast + ":" + slow + ":" + signal, nanFill,
					() -> new VolumeWeightedMacd(fast, slow, signal),
					(i, b) -> (cast i : VolumeWeightedMacd).update(b));
			}
		};
	}
}
