package musescript.ew;

/**
 * Bucket C4 — documented warmup floors for forecast hosts and benchmark runners.
 *
 * Anchors / evals must not start before enough history. These constants match the CLI defaults;
 * `isLegalAnchor` is the shared guard the runners (and tests) use.
 */
class HostWarmup {
	/** `EwBenchmarkCli --warmup` default (swing lattice needs pivots). */
	public static inline var EW_LATTICE_BENCHMARK:Int = 60;
	/** `RegimeBenchmarkCli --warmup` default (MH window + burn-in). */
	public static inline var REGIME_BENCHMARK:Int = 180;
	/** `AuctionBenchmarkCli --warmup` default (≥ typical VP window). */
	public static inline var AUCTION_BENCHMARK:Int = 120;

	/** `RegimeForecastHost` empty-cloud floor (return count). */
	public static inline var REGIME_MIN_RETURNS:Int = RegimeForecastHost.MIN_RETURNS;
	/** Auction needs a full VP window ending at t before a non-empty cloud. */
	public static inline var AUCTION_DEFAULT_WINDOW:Int = 20;

	/**
	 * Legal benchmark anchor: past warmup, on the step grid, and with room for a forward horizon.
	 * Mirrors the three `*BenchmarkCli` loops.
	 */
	public static function isLegalAnchor(
		t:Int, warmup:Int, step:Int, horizon:Int, nBars:Int
	):Bool {
		if (t < warmup) return false;
		if (step < 1) step = 1;
		if ((t - warmup) % step != 0) return false;
		if (t + horizon >= nBars) return false;
		return true;
	}

	/** True when a regime host has enough returns through bar `t` (t ≥ MIN_RETURNS). */
	public static function regimeReady(t:Int):Bool {
		// After onBar(t), returnsThrough(t) has length t (closes 1..t).
		return t >= REGIME_MIN_RETURNS;
	}

	/** True when an auction host with `window` can assemble a profile ending at `t`. */
	public static function auctionReady(t:Int, window:Int = AUCTION_DEFAULT_WINDOW):Bool {
		var w = window < 2 ? 2 : window;
		return t >= w - 1;
	}
}
