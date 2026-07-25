package musescript.harness;

class Metrics {
	public static function sharpe(returns:Array<Float>, rf:Float):Float {
		if (returns.length < 2) return 0;
		var mean = 0.0;
		for (r in returns) mean += r;
		mean /= returns.length;
		var var_ = 0.0;
		for (r in returns) {
			var d = r - mean;
			var_ += d * d;
		}
		var_ /= returns.length - 1;
		var std = Math.sqrt(var_);
		if (std == 0) return 0;
		return ((mean - rf) / std) * Math.sqrt(252);
	}

	/**
	 * Sortino ratio: excess mean return over downside deviation of returns
	 * below `rf`, annualized like `sharpe` (`* sqrt(252)`). Returns 0 when
	 * the sample is too short or downside deviation is zero.
	 */
	public static function sortino(returns:Array<Float>, rf:Float):Float {
		if (returns.length < 2) return 0;
		var mean = 0.0;
		for (r in returns) mean += r;
		mean /= returns.length;
		var down = 0.0;
		var nDown = 0;
		for (r in returns) {
			if (r < rf) {
				var d = r - rf;
				down += d * d;
				nDown++;
			}
		}
		if (nDown == 0) return 0;
		var downside = Math.sqrt(down / returns.length);
		if (downside == 0) return 0;
		return ((mean - rf) / downside) * Math.sqrt(252);
	}

	public static function maxDrawdown(equity:Array<Float>):Float {
		var peak = Math.NEGATIVE_INFINITY;
		var maxDd = 0.0;
		for (e in equity) {
			if (e > peak) peak = e;
			var dd = peak > 0 ? (peak - e) / peak : 0;
			if (dd > maxDd) maxDd = dd;
		}
		return maxDd;
	}

	/**
	 * `prev <= 0` (not just `prev != 0`) is the guard that matters: a percentage return against a
	 * non-positive capital base is meaningless, and WORSE than meaningless once `prev` is actually
	 * NEGATIVE -- `(equity[i] - prev) / prev` divides two negative numbers whenever the account
	 * keeps losing money (equity[i] even more negative than prev), producing a spurious POSITIVE
	 * "return" for every further loss. A real genome found this: `size` grown to a raw `volume`
	 * scalar (buying/shorting literally the bar's share volume every trade) blew the account to
	 * -$11B equity, and this sign-inversion then scored that catastrophe as the SINGLE BEST
	 * strategy of an entire session (Sharpe 4.6655 vs every honest champion's 0.4-0.9) -- evolution
	 * doesn't know the difference between a real edge and an exploitable scoring bug, so a fitness
	 * function with an exploitable blind spot WILL eventually get selected for, given enough
	 * generations across a wide-enough search. Once capital is gone there's nothing left to
	 * "return" on -- every return from that point on is a flat 0.0, not a fabricated positive one.
	 * The wipeout transition itself (the one bar where `prev` was still positive) is untouched and
	 * still computes a correctly-signed, appropriately catastrophic large-negative return.
	 */
	public static function returnsFromEquity(equity:Array<Float>):Array<Float> {
		var out = [];
		for (i in 1...equity.length) {
			var prev = equity[i - 1];
			out.push(prev > 0 ? (equity[i] - prev) / prev : 0.0);
		}
		return out;
	}

	public static function winRate(wins:Int, trades:Int):Float {
		return trades == 0 ? 0 : wins / trades;
	}
}
