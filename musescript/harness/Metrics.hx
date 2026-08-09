package musescript.harness;

class Metrics {
	/**
	 * Trading days per year — the annualization factor for DAILY bars, and the default
	 * everywhere so existing daily results are unchanged.
	 *
	 * ⚠️ It is only correct for daily data. A 15-minute strategy annualized at `sqrt(252)`
	 * understates its annualized Sharpe by roughly `sqrt(26)`, so Sharpes computed at
	 * different resolutions are NOT on a common scale and must not be ranked against each
	 * other. Use `periodsPerYearFromBarSeconds` / `configureFromBars` for sub-daily tapes.
	 * (The indicator library already parameterizes this — see `HistoricalVolatility`'s
	 * `annualizationFactor` and `Parkinson`/`RogersSatchell`/`YangZhang`'s `trading_periods`;
	 * this brings the fitness path in line with that.)
	 */
	public static inline var DAILY_PERIODS_PER_YEAR:Float = 252.0;

	/**
	 * Process-level Sharpe annualization factor for harness / fitness paths that omit an
	 * explicit override. Ownership point for OPEN_ITEMS **1.4**:
	 *
	 * - Default stays `DAILY_PERIODS_PER_YEAR` (252) so daily goldens / synthetic unit tapes
	 *   keep parity — `BarFeed.synthetic` uses `time = i*60`, which must NOT silently flip
	 *   annualization.
	 * - Callers with known sub-daily (or non-session daily) spacing set this explicitly, or
	 *   call `configureFromBars` (opt-in). Fitness never auto-infers on every `evaluate`.
	 * - Calendar-day spacing (~86400s) configures to **252** (equity session convention), not
	 *   `periodsPerYearFromBarSeconds(86400)=365`. Continuous-market daily must set 365 by hand.
	 */
	public static var periodsPerYear:Float = DAILY_PERIODS_PER_YEAR;

	/** Restore the daily-252 default (tests / session teardown). */
	public static inline function resetPeriodsPerYear():Void {
		periodsPerYear = DAILY_PERIODS_PER_YEAR;
	}

	/**
	 * Annualization factor for a tape whose bars are `barSeconds` apart, assuming a
	 * continuously-traded market (crypto/FX: 365×24h). For session-based markets scale by the
	 * session length instead — e.g. a 6.5h equity session at 15m bars is `252 * 26`, which is
	 * `periodsPerYearFromBarSeconds(900, 6.5 * 3600, 252)`.
	 *
	 * @param barSeconds     seconds between consecutive bars (900 for 15m, 86400 for daily)
	 * @param sessionSeconds tradable seconds per session (default 24h — continuous markets)
	 * @param sessionsPerYear sessions per year (default 365 — continuous markets)
	 */
	public static function periodsPerYearFromBarSeconds(barSeconds:Float,
			sessionSeconds:Float = 86400.0, sessionsPerYear:Float = 365.0):Float {
		if (!(barSeconds > 0) || !(sessionSeconds > 0) || !(sessionsPerYear > 0)) return DAILY_PERIODS_PER_YEAR;
		return (sessionSeconds / barSeconds) * sessionsPerYear;
	}

	/**
	 * Median consecutive `Bar.time` delta when spacing looks regular; else `null`.
	 * Does not mutate `periodsPerYear` — pair with `configureFromBars` / `setPeriodsPerYear`.
	 */
	public static function inferBarSeconds(bars:Array<Bar>):Null<Float> {
		if (bars == null || bars.length < 2) return null;
		var deltas:Array<Float> = [];
		var i = 1;
		while (i < bars.length) {
			var dt = bars[i].time - bars[i - 1].time;
			if (Math.isFinite(dt) && dt > 0) deltas.push(dt);
			i++;
		}
		if (deltas.length < 1) return null;
		deltas.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var med = deltas[Std.int(deltas.length / 2)];
		if (!(med > 0)) return null;
		var ok = 0;
		for (d in deltas) {
			if (Math.abs(d - med) <= med * 0.10) ok++;
		}
		if (ok < Math.ceil(deltas.length * 0.80)) return null;
		return med;
	}

	/**
	 * Opt-in: set `periodsPerYear` from tape timestamps.
	 * Daily (~86400s) → 252. Sub-daily → `periodsPerYearFromBarSeconds` (continuous defaults
	 * unless `sessionSeconds` / `sessionsPerYear` passed). Returns the factor set, or null if
	 * spacing could not be inferred (leaves prior `periodsPerYear` unchanged).
	 */
	public static function configureFromBars(bars:Array<Bar>,
			?sessionSeconds:Float, ?sessionsPerYear:Float):Null<Float> {
		var bs = inferBarSeconds(bars);
		if (bs == null) return null;
		// Equity daily convention: do not silently leap to continuous-market 365.
		if (Math.abs(bs - 86400.0) <= 86400.0 * 0.05) {
			periodsPerYear = DAILY_PERIODS_PER_YEAR;
			return periodsPerYear;
		}
		var sess = sessionSeconds != null ? sessionSeconds : 86400.0;
		var spy = sessionsPerYear != null ? sessionsPerYear : 365.0;
		periodsPerYear = periodsPerYearFromBarSeconds(bs, sess, spy);
		return periodsPerYear;
	}

	/** Clamp and install an explicit annualization factor. */
	public static function setPeriodsPerYear(py:Float):Void {
		periodsPerYear = (py > 0 && Math.isFinite(py)) ? py : DAILY_PERIODS_PER_YEAR;
	}

	/**
	 * Annualized sample Sharpe. When `periodsPerYearOverride` is omitted, uses the process
	 * `Metrics.periodsPerYear` (default 252).
	 *
	 * ⚠️ **Two other implementations of this exact algorithm exist on purpose** —
	 * `OrderSim.sharpeOnline` and `NmaFitness.sharpeOfEquity` — as allocation-free variants
	 * that avoid materializing the equity/returns arrays in hot paths. Both are documented
	 * as bit-exact with this one, and `Fitness.assertNmaParity` compares the NMA and compiled
	 * paths at 1e-9, so **any change to the arithmetic here must be made identically in all
	 * three**. `TestEvoVariation.testSharpeImplementationsAgreeBitExactly` enforces that.
	 *
	 * Deliberately NOT switched to Welford/Kahan: the two-pass form below is already the
	 * numerically sound one (strictly better than the naive `E[x²]−E[x]²`), the accuracy
	 * difference on realistic return series is sub-ULP, and changing it would silently break
	 * the bit-exactness contract above for no measurable gain.
	 */
	public static function sharpe(returns:Array<Float>, rf:Float,
			?periodsPerYearOverride:Null<Float>):Float {
		var py = periodsPerYearOverride != null ? periodsPerYearOverride : periodsPerYear;
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
		return ((mean - rf) / std) * Math.sqrt(py);
	}

	/**
	 * Sortino ratio: excess mean return over downside deviation of returns below `rf`,
	 * annualized like `sharpe` (omitted override → `Metrics.periodsPerYear`, default 252).
	 * Returns 0 when the sample is too short or downside deviation is zero.
	 *
	 * Note the denominator convention: the squared downside deviations are divided by the
	 * FULL sample size, not by the count of downside observations. That is the standard
	 * target-semideviation definition (upside observations contribute a deviation of zero),
	 * and it is intentional — stated here because the alternative convention is common
	 * enough that the `/ returns.length` next to an `nDown` counter reads like a bug.
	 */
	public static function sortino(returns:Array<Float>, rf:Float,
			?periodsPerYearOverride:Null<Float>):Float {
		var py = periodsPerYearOverride != null ? periodsPerYearOverride : periodsPerYear;
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
		return ((mean - rf) / downside) * Math.sqrt(py);
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
