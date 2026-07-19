package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Initial Balance output: the high/low range established by the opening bars. */
typedef InitialBalanceOutput = {
	var high:Float;
	var low:Float;
}

/**
 * Initial Balance: the high/low range established over the first `ibBars`
 * bars of the series, held fixed for every bar thereafter — a bar-count
 * analogue of the "first N minutes of the session" range floor-traders use
 * as a reference level, without depending on wall-clock session boundaries
 * (see `AverageDailyRange`'s civil-calendar caveat).
 */
class InitialBalance implements MuseIndicator<Bar, InitialBalanceOutput> {
	var ibBars:Int;
	var count:Int;
	var high:Float;
	var low:Float;

	public function new(ibBars:Int) {
		if (ibBars <= 0) throw "InitialBalance: ibBars must be > 0";
		this.ibBars = ibBars;
		count = 0;
		high = Math.NEGATIVE_INFINITY;
		low = Math.POSITIVE_INFINITY;
	}

	public function update(bar:Bar):Null<InitialBalanceOutput> {
		if (count < ibBars) {
			if (bar.high > high) high = bar.high;
			if (bar.low < low) low = bar.low;
			count++;
		}
		if (count < ibBars) return null;
		return { high: high, low: low };
	}

	public function reset():Void {
		count = 0;
		high = Math.NEGATIVE_INFINITY;
		low = Math.POSITIVE_INFINITY;
	}

	public function warmupPeriod():Int return ibBars;
	public function isReady():Bool return count >= ibBars;
	public function name():String return "InitialBalance";

	public static function spec():IndicatorSpec {
		return {
			name: "initial_balance", args: [TWindow], ret: TObject([
				{name: "high", ty: TScalar}, {name: "low", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 6);
				return IndicatorCache.evalBar(h, "initial_balance:" + p, { high: Math.NaN, low: Math.NaN },
					() -> new InitialBalance(p), (i, b) -> (cast i : InitialBalance).update(b));
			}
		};
	}
}
