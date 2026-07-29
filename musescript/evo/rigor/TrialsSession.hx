package musescript.evo.rigor;

/**
 * Session trials counter for DSR deflation (Initiative 1.3).
 *
 * Muse-script owns the counter so evo / CLI / WASM hosts share one hook.
 * The IDE must either:
 *   (a) call `recordTrial()` once per distinct strategy variant backtested in the
 *       session, then pass `getCount()` as `nTrials` into `TruthReport.evaluate`, OR
 *   (b) maintain its own count and pass it via `TrialsSession.setCount(n)` /
 *       `TruthReportOpts.nTrials` before evaluating.
 *
 * Higher `nTrials` raises the DSR bar (anti-p-hacking). Default count is 0 until
 * the host records; `effectiveTrials` clamps to ≥ 1 for ProbSharpe.
 *
 * «μὴ ἁρπάζειν τὴν τύχην πολλάκις.»
 */
class TrialsSession {
	static var count:Int = 0;

	/** Reset at the start of a user session / Studio workspace. */
	public static function reset():Void {
		count = 0;
	}

	/** Current session trial count (may be 0 before any backtest). */
	public static inline function getCount():Int {
		return count;
	}

	/**
	 * Host-owned override when the IDE tracks variants outside muse-script
	 * (e.g. persisted session state). Clamps negatives to 0.
	 */
	public static function setCount(n:Int):Void {
		count = n < 0 ? 0 : n;
	}

	/**
	 * Record one strategy-variant backtest. Returns the new count.
	 * Call once per distinct variant the user tried this session.
	 */
	public static function recordTrial():Int {
		count++;
		return count;
	}

	/** Value to feed ProbSharpe / OosVerdict / TruthReport (`max(1, count)`). */
	public static inline function effectiveTrials():Int {
		return count < 1 ? 1 : count;
	}
}
