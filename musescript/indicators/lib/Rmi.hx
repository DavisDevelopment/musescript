package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Relative Momentum Index (RMI) — ported from wickra-core's `Rmi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rmi.rs).
 *
 * RSI generalised to a multi-bar momentum lookback. The RMI (Roger Altman, 1993)
 * compares each close to the close `momentum` bars ago, then applies the same
 * Wilder-smoothed up/down accumulator over `period`. With `momentum = 1`, the
 * RMI reduces exactly to the RSI.
 */
class Rmi implements MuseIndicator<Float, Float> {
	var period:Int;
	var momentum:Int;
	var window:RingBuffer<Float>;
	var seedGains:Array<Float>;
	var seedLosses:Array<Float>;
	var avgGain:Null<Float>;
	var avgLoss:Null<Float>;
	var lastValue:Null<Float>;

	public function new(period:Int, momentum:Int) {
		if (period <= 0 || momentum <= 0) throw "Rmi: period and momentum must be > 0";
		this.period = period;
		this.momentum = momentum;
		this.window = new RingBuffer(momentum);
		this.seedGains = [];
		this.seedLosses = [];
		this.avgGain = null;
		this.avgLoss = null;
		this.lastValue = null;
	}

	static function rmiFromAvgs(avgGain:Float, avgLoss:Float):Float {
		var denom = avgGain + avgLoss;
		if (denom == 0.0) {
			return 50.0;
		} else {
			return 100.0 * (avgGain / denom);
		}
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return lastValue;
		}

		if (!window.isFull()) {
			// Still filling the momentum lookback
			window.push(input);
			return null;
		}

		// Eviction returns the close `momentum` bars ago.
		var past = window.push(input);

		var change = input - past;
		var gain = if (change > 0.0) change else 0.0;
		var loss = if (change < 0.0) -change else 0.0;

		if (avgGain != null && avgLoss != null) {
			var n = period;
			var newAg = (avgGain * (n - 1.0) + gain) / n;
			var newAl = (avgLoss * (n - 1.0) + loss) / n;
			avgGain = newAg;
			avgLoss = newAl;
			var v = rmiFromAvgs(newAg, newAl);
			lastValue = v;
			return v;
		}

		seedGains.push(gain);
		seedLosses.push(loss);
		if (seedGains.length == period) {
			var ag = 0.0;
			for (g in seedGains) ag += g;
			ag /= period;
			var al = 0.0;
			for (l in seedLosses) al += l;
			al /= period;
			avgGain = ag;
			avgLoss = al;
			var v = rmiFromAvgs(ag, al);
			lastValue = v;
			return v;
		}

		return null;
	}

	public function reset():Void {
		window = new RingBuffer(momentum);
		seedGains = [];
		seedLosses = [];
		avgGain = null;
		avgLoss = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return momentum + period;
	public function isReady():Bool return lastValue != null;
	public function name():String return "RMI";

	public static function spec():IndicatorSpec {
		return {
			name: "rmi", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var period = IndicatorCache.intArg(args, 1, 14);
				var momentum = IndicatorCache.intArg(args, 2, 5);
				return IndicatorCache.evalSeries(h, "rmi:" + series + ":" + period + ":" + momentum, series, Math.NaN,
					() -> new Rmi(period, momentum), (i, v) -> (cast i : Rmi).update(v));
			}
		};
	}
}
