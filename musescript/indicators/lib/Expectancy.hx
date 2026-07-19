package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Trade Expectancy (Van Tharp): the average result per trade, expressed in
 * units of the average loss, over a trailing window of `period` trade
 * P&L values.
 *
 * winRate = count(pnl > 0) / n
 * avgWin  = mean(pnl over winning trades)      (0 if no wins)
 * avgLoss = mean(|pnl| over losing trades)     (0 if no losses)
 * Expectancy = winRate * avgWin - (1 - winRate) * avgLoss
 *
 * Positive means the system has a positive edge per trade on average over
 * the window; negative means it's losing money on average.
 */
class Expectancy implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Expectancy: period must be > 0";
		this.period = period;
		window = [];
	}

	public function update(pnl:Float):Null<Float> {
		if (!Math.isFinite(pnl)) return null;
		if (window.length == period) window.shift();
		window.push(pnl);
		if (window.length < period) return null;

		var wins = 0;
		var sumWin = 0.0;
		var losses = 0;
		var sumLoss = 0.0;
		for (p in window) {
			if (p > 0.0) { wins++; sumWin += p; }
			else if (p < 0.0) { losses++; sumLoss += -p; }
		}
		var n = window.length;
		var winRate = wins / n;
		var avgWin = wins > 0 ? sumWin / wins : 0.0;
		var avgLoss = losses > 0 ? sumLoss / losses : 0.0;
		return winRate * avgWin - (1.0 - winRate) * avgLoss;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Expectancy";

	public static function spec():IndicatorSpec {
		return {
			name: "expectancy", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "expectancy:" + series + ":" + p, series, Math.NaN,
					() -> new Expectancy(p), (i, v) -> (cast i : Expectancy).update(v));
			}
		};
	}
}
