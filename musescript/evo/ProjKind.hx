package musescript.evo;

/**
 * What future quantity a projection forecasts — fixes the leakage-free scoring target for the
 * projection-skill fitness term (PROJECTION_COEVOLUTION_PLAN.md §6). A projection is *interpreted*
 * as relating to the future via its `kind`; it never reads future data (that lives only in the
 * scorer, never in the eval the policy consumes).
 */
enum ProjKind {
	/** Forward return: `close[t+H]/close[t] - 1`. */
	PReturn;
	/** Forward sign: `sign(close[t+H] - close[t])`. */
	PDirection;
	/** Forward level: `close[t+H]`. */
	PLevel;
	/** Forward realized volatility over `(t, t+H]`. */
	PVol;
	/** Forward high-low range over `(t, t+H]`. */
	PRange;
}
