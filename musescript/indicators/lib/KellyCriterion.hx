package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Kelly Criterion: the theoretically edge-maximizing fraction of capital to
 * risk per trade, derived from the win rate and win/loss size ratio
 * observed over a trailing window of `period` trade P&L values.
 *
 * winRate = count(pnl > 0) / n
 * winLossRatio = avgWin / avgLoss           (both positive magnitudes)
 * Kelly = winRate - (1 - winRate) / winLossRatio
 *
 * Positive means the edge favors sizing up; negative means the system has a
 * negative edge under Kelly's assumptions (position size should be zero).
 * Falls back to 0 when there have been no losses in the window (undefined
 * ratio with zero in the denominator).
 */
class KellyCriterion implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "KellyCriterion: period must be > 0";
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
		if (losses == 0) return 0.0;
		var avgWin = wins > 0 ? sumWin / wins : 0.0;
		var avgLoss = sumLoss / losses;
		if (avgLoss == 0.0) return 0.0;
		var winLossRatio = avgWin / avgLoss;
		if (winLossRatio == 0.0) return 0.0;
		return winRate - (1.0 - winRate) / winLossRatio;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "KellyCriterion";

	public static function spec():IndicatorSpec {
		return {
			name: "kelly_criterion", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "kelly_criterion:" + series + ":" + p, series, Math.NaN,
					() -> new KellyCriterion(p), (i, v) -> (cast i : KellyCriterion).update(v));
			}
		};
	}
}
