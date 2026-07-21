package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;
import musescript.indicators.prim.StdDev;
import musescript.indicators.prim.Sma;

/**
 * Dynamic Momentum Index (Chande's volatility-adaptive RSI) — ported from wickra-core's `DynamicMomentumIndex`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/dynamic_momentum_index.rs).
 *
 * Tushar Chande's RSI variant whose lookback period shrinks in volatile markets
 * and lengthens in calm ones, keeping the oscillator responsive during fast moves
 * and smooth during quiet periods.
 *
 * vol     = StdDev(close, 5)
 * vol_avg = SMA(vol, 10)
 * Vi      = vol / vol_avg                    // volatility index
 * td      = clamp(round(period / Vi), 5, 30) // dynamic lookback
 * avg_gain, avg_loss = simple means of the last `td` price changes
 * DMI     = 100 * avg_gain / (avg_gain + avg_loss)
 *
 * Output is bounded in [0, 100]; a flat market returns 50.
 * The first value lands after MAX_PERIOD + 1 = 31 inputs.
 */
class DynamicMomentumIndex implements MuseIndicator<Float, Float> {
	static inline var STD_PERIOD = 5;
	static inline var STD_AVG_PERIOD = 10;
	static inline var MIN_PERIOD = 5;
	static inline var MAX_PERIOD = 30;

	var period:Int;
	var vol:StdDev;
	var volAvg:Sma;
	var prevClose:Null<Float>;
	var changes:Array<Float>;
	var lastVolAvg:Null<Float>;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "DynamicMomentumIndex: period must be > 0";
		this.period = period;
		vol = new StdDev(STD_PERIOD);
		volAvg = new Sma(STD_AVG_PERIOD);
		prevClose = null;
		changes = [];
		lastVolAvg = null;
		lastValue = null;
	}

	function dynamicPeriod(v:Float, vAvg:Float):Int {
		if (vAvg <= 0.0 || v <= 0.0) {
			// No measurable volatility -> slowest (calmest) lookback
			return MAX_PERIOD;
		}
		var vi = v / vAvg;
		var td = Math.round(period / vi);
		// Clamp into the valid band
		return Std.int(Math.max(MIN_PERIOD, Math.min(MAX_PERIOD, td)));
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return lastValue;

		// Track the smoothed volatility on every close
		if (vol.update(input) != null) {
			var volValue = vol.value();
			lastVolAvg = volAvg.update(volValue);
		}

		// Record the price change
		if (prevClose != null) {
			var change = input - prevClose;
			if (changes.length == MAX_PERIOD) {
				changes.shift();
			}
			changes.push(change);
		}
		prevClose = input;

		// `vol.value()` returns a plain (non-nullable) Float -- only `lastVolAvg`
		// (set from StdDev/Sma's genuinely-Null<Float> `update()`) can signal "not
		// ready yet". The old `vol.value() == null` half was always false on
		// dynamic targets (dead code) and doesn't type-check at all on static
		// targets (Float can't hold null) -- dropped, not a behavior change.
		if (lastVolAvg == null) return null;
		var volValue = vol.value();
		var volAvgValue = lastVolAvg;

		if (changes.length < MAX_PERIOD) {
			return null;
		}

		var td = dynamicPeriod(volValue, volAvgValue);
		// Average gains and losses over the last `td` changes
		var sumGain = 0.0;
		var sumLoss = 0.0;
		for (i in (MAX_PERIOD - td)...MAX_PERIOD) {
			var c = changes[i];
			if (c > 0.0) {
				sumGain += c;
			} else if (c < 0.0) {
				sumLoss -= c;
			}
		}
		var denom = sumGain + sumLoss;
		var v = if (denom == 0.0) {
			50.0;
		} else {
			100.0 * (sumGain / denom);
		};
		lastValue = v;
		return v;
	}

	public function reset():Void {
		vol.reset();
		volAvg.reset();
		prevClose = null;
		changes = [];
		lastVolAvg = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return MAX_PERIOD + 1;
	public function isReady():Bool return lastValue != null;
	public function name():String return "DynamicMomentumIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "dynamic_momentum_index", args: [TSeries, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var period = IndicatorCache.intArg(args, 1, 14);
				var key = "dmi:" + series + ":" + period;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new DynamicMomentumIndex(period), (i, v) -> (cast i : DynamicMomentumIndex).update(v));
			}
		};
	}
}
